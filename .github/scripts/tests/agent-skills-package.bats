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

  # shellcheck disable=SC2016
  run env \
    GITHUB_WORKSPACE="${workspace}" \
    RUNNER_TEMP="${runner_temp}" \
    SKILLS_DIRECTORY="${skills_directory}" \
    bash -c 'cd "$1" && exec bash -euo pipefail "$2"' _ "${workspace}" "${STEP_SCRIPT}"
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

@test "an explicit release tag enables attachment with release-event fallback" {
  local attach_condition
  local release_tag_env

  [ "$(yq -r '.on.workflow_call.inputs."release-tag".type' "${WORKFLOW}")" = 'string' ]
  [ "$(yq -r '.on.workflow_call.inputs."release-tag".default' "${WORKFLOW}")" = 'null' ]
  attach_condition="$(yq -r '.jobs."attach-to-release".if' "${WORKFLOW}")"
  [ "${attach_condition}" = "github.event_name == 'release' || inputs.release-tag != ''" ]
  release_tag_env="$(yq -r '.jobs."attach-to-release".steps[] | select(.name == "Attach packaged skills to the release") | .env.RELEASE_TAG' "${WORKFLOW}")"
  [ "${release_tag_env}" = "\${{ inputs.release-tag || github.event.release.tag_name }}" ]
  [ "$(yq -r '.jobs.package.steps[] | select(.name == "Checkout repository") | .with.ref' "${WORKFLOW}")" = "\${{ inputs.release-tag || github.sha }}" ]
}

@test "release attachment uploads per-skill ZIPs using the selected tag" {
  local attach_script="${TEST_TEMP}/attach-skills.sh"
  local bin_dir="${TEST_TEMP}/bin"
  local runner_temp="${TEST_TEMP}/runner"

  yq -r '.jobs."attach-to-release".steps[] | select(.name == "Attach packaged skills to the release") | .run' "${WORKFLOW}" > "${attach_script}"
  mkdir -p "${bin_dir}" "${runner_temp}/agent-skill-release-assets"
  touch "${runner_temp}/agent-skill-release-assets/alpha.zip"
  cat > "${bin_dir}/gh" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${RUNNER_TEMP}/gh-args"
EOF
  chmod +x "${bin_dir}/gh"

  run env PATH="${bin_dir}:${PATH}" RUNNER_TEMP="${runner_temp}" \
    RELEASE_TAG=v2.3.4 REPOSITORY=dceoy/example GH_TOKEN=test \
    bash -euo pipefail "${attach_script}"

  [ "${status}" -eq 0 ]
  [ "$(sed -n '1p' "${runner_temp}/gh-args")" = 'release' ]
  [ "$(sed -n '2p' "${runner_temp}/gh-args")" = 'upload' ]
  [ "$(sed -n '3p' "${runner_temp}/gh-args")" = 'v2.3.4' ]
  [ "$(sed -n '4p' "${runner_temp}/gh-args")" = "${runner_temp}/agent-skill-release-assets/alpha.zip" ]
  [ "$(sed -n '5p' "${runner_temp}/gh-args")" = '--repo' ]
  [ "$(sed -n '6p' "${runner_temp}/gh-args")" = 'dceoy/example' ]
  [ "$(sed -n '7p' "${runner_temp}/gh-args")" = '--clobber' ]
}
