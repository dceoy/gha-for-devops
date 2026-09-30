#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/agent-skills-package.yml"
  TEST_TEMP="$(mktemp -d)"
  STEP_SCRIPT="${TEST_TEMP}/package-skills.sh"
  yq -r '.jobs.package.steps[] | select(.name == "Package skills") | .run' "${WORKFLOW}" > "${STEP_SCRIPT}"
}

teardown() {
  rm -rf "${TEST_TEMP}"
}

run_packaging() {
  local workspace="$1"
  local runner_temp="$2"
  local skills_directory="$3"

  run env \
    GITHUB_WORKSPACE="${workspace}" \
    RUNNER_TEMP="${runner_temp}" \
    SKILLS_DIRECTORY="${skills_directory}" \
    bash -euo pipefail "${STEP_SCRIPT}"
}

@test "packages each skill as a standalone zip with a safe top-level path" {
  local workspace="${TEST_TEMP}/workspace"
  local runner_temp="${TEST_TEMP}/runner"
  local alpha_archive="${runner_temp}/agent-skill-packages/alpha.zip"
  local beta_archive="${runner_temp}/agent-skill-packages/-beta.zip"
  local entries

  mkdir -p "${workspace}/skills/alpha/references" "${workspace}/skills/-beta"
  printf '# alpha\n' > "${workspace}/skills/alpha/SKILL.md"
  printf 'details\n' > "${workspace}/skills/alpha/references/details.md"
  printf '# beta\n' > "${workspace}/skills/-beta/SKILL.md"

  run_packaging "${workspace}" "${runner_temp}" skills

  [ "${status}" -eq 0 ]
  [ -f "${alpha_archive}" ]
  [ -f "${beta_archive}" ]

  entries="$(unzip -Z1 "${alpha_archive}")"
  [[ "${entries}" == *"alpha/SKILL.md"* ]]
  [[ "${entries}" == *"alpha/references/details.md"* ]]
  [ "$(printf '%s\n' "${entries}" | grep -Ec '(^|/)SKILL\.md$')" -eq 1 ]
  [ "$(unzip -p "${alpha_archive}" alpha/SKILL.md)" = '# alpha' ]

  entries="$(unzip -Z1 "${beta_archive}")"
  [[ "${entries}" == *"-beta/SKILL.md"* ]]
}

@test "rejects a skill containing a directory symlink" {
  local workspace="${TEST_TEMP}/workspace"
  local runner_temp="${TEST_TEMP}/runner"
  local outside_dir="${TEST_TEMP}/outside"

  mkdir -p "${workspace}/skills/leaky" "${outside_dir}"
  printf '# leaky\n' > "${workspace}/skills/leaky/SKILL.md"
  printf 'private data\n' > "${outside_dir}/private.txt"
  ln -s "${outside_dir}" "${workspace}/skills/leaky/external"

  run_packaging "${workspace}" "${runner_temp}" skills

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"symbolic link"* ]]
  [ ! -e "${runner_temp}/agent-skill-packages/leaky.zip" ]
}

@test "rejects a skills directory outside the workspace" {
  local workspace="${TEST_TEMP}/workspace"
  local runner_temp="${TEST_TEMP}/runner"
  local outside_skills="${TEST_TEMP}/outside-skills"

  mkdir -p "${workspace}" "${outside_skills}/example"
  printf '# example\n' > "${outside_skills}/example/SKILL.md"

  run_packaging "${workspace}" "${runner_temp}" "${outside_skills}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"must resolve inside GITHUB_WORKSPACE"* ]]
}

@test "fails when the skills directory contains no skills" {
  local workspace="${TEST_TEMP}/workspace"
  local runner_temp="${TEST_TEMP}/runner"

  mkdir -p "${workspace}/skills"

  run_packaging "${workspace}" "${runner_temp}" skills

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"no skills found"* ]]
}
