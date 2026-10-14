#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/agent-skills-package.yml"
  TEST_TEMP="$(mktemp -d)"
  DISCOVER_SCRIPT="${TEST_TEMP}/discover-skills.sh"
  PACKAGE_SCRIPT="${TEST_TEMP}/package-skill.sh"
  yq -r '.jobs.discover.steps[] | select(.name == "Discover skills") | .run' "${WORKFLOW}" > "${DISCOVER_SCRIPT}"
  yq -r '.jobs.package.steps[] | select(.name == "Package skill") | .run' "${WORKFLOW}" > "${PACKAGE_SCRIPT}"
}

teardown() {
  rm -rf "${TEST_TEMP}"
}

run_discovery() {
  local workspace="$1"
  local skills_directory="$2"
  local output_file="$3"

  run env \
    GITHUB_WORKSPACE="${workspace}" \
    GITHUB_OUTPUT="${output_file}" \
    SKILLS_DIRECTORY="${skills_directory}" \
    ARTIFACT_NAME=agent-skills \
    bash -c 'cd "$1" && exec bash -euo pipefail "$2"' _ "${workspace}" "${DISCOVER_SCRIPT}"
}

run_packaging() {
  local workspace="$1"
  local runner_temp="$2"
  local skills_directory="$3"
  local skill_name="$4"

  run env \
    GITHUB_WORKSPACE="${workspace}" \
    RUNNER_TEMP="${runner_temp}" \
    SKILLS_DIRECTORY="${skills_directory}" \
    SKILL_NAME="${skill_name}" \
    bash -c 'cd "$1" && exec bash -euo pipefail "$2"' _ "${workspace}" "${PACKAGE_SCRIPT}"
}

@test "discovers each skill and exposes individual artifact names" {
  local workspace="${TEST_TEMP}/workspace"
  local output_file="${TEST_TEMP}/discovery-output"

  mkdir -p "${workspace}/skills/alpha" "${workspace}/skills/-beta"
  printf '# alpha\n' > "${workspace}/skills/alpha/SKILL.md"
  printf '# beta\n' > "${workspace}/skills/-beta/SKILL.md"

  run_discovery "${workspace}" skills "${output_file}"
  [ "${status}" -eq 0 ]

  run bash -c 'grep "^skills=" "$1" | cut -d= -f2- | jq -e '\''sort == ["-beta", "alpha"]'\''' _ "${output_file}"
  [ "${status}" -eq 0 ]
  run bash -c 'grep "^artifact-names=" "$1" | cut -d= -f2- | jq -e '\''sort == ["agent-skills--beta", "agent-skills-alpha"]'\''' _ "${output_file}"
  [ "${status}" -eq 0 ]
}

@test "packages each selected skill independently as a standalone ZIP" {
  local workspace="${TEST_TEMP}/workspace"
  local runner_temp="${TEST_TEMP}/runner"
  local alpha_archive="${runner_temp}/agent-skill-packages/alpha.zip"
  local beta_archive="${runner_temp}/agent-skill-packages/-beta.zip"
  local entries

  mkdir -p "${workspace}/skills/alpha/references" "${workspace}/skills/-beta"
  printf '# alpha\n' > "${workspace}/skills/alpha/SKILL.md"
  printf 'details\n' > "${workspace}/skills/alpha/references/details.md"
  printf '# beta\n' > "${workspace}/skills/-beta/SKILL.md"

  run_packaging "${workspace}" "${runner_temp}" skills alpha

  [ "${status}" -eq 0 ]
  [ -f "${alpha_archive}" ]
  [ ! -e "${beta_archive}" ]

  entries="$(unzip -Z1 "${alpha_archive}")"
  [[ "${entries}" == *"alpha/SKILL.md"* ]]
  [[ "${entries}" == *"alpha/references/details.md"* ]]
  [ "$(printf '%s\n' "${entries}" | grep -Ec '(^|/)SKILL\.md$')" -eq 1 ]
  [ "$(unzip -p "${alpha_archive}" alpha/SKILL.md)" = '# alpha' ]

  run_packaging "${workspace}" "${runner_temp}" skills -beta
  [ "${status}" -eq 0 ]
  [ -f "${beta_archive}" ]
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

  run_packaging "${workspace}" "${runner_temp}" skills leaky

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"symbolic link"* ]]
  [ ! -e "${runner_temp}/agent-skill-packages/leaky.zip" ]
}

@test "rejects a skills directory outside the workspace" {
  local workspace="${TEST_TEMP}/workspace"
  local outside_skills="${TEST_TEMP}/outside-skills"

  mkdir -p "${workspace}" "${outside_skills}/example"
  printf '# example\n' > "${outside_skills}/example/SKILL.md"

  run_discovery "${workspace}" "${outside_skills}" "${TEST_TEMP}/output"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"must resolve inside GITHUB_WORKSPACE"* ]]
}

@test "rejects names that cannot be used safely for individual artifacts" {
  local workspace="${TEST_TEMP}/workspace"

  mkdir -p "${workspace}/skills/has space"
  printf '# invalid\n' > "${workspace}/skills/has space/SKILL.md"

  run_discovery "${workspace}" skills "${TEST_TEMP}/output"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not artifact-safe"* ]]
}

@test "fails when the skills directory contains no skills" {
  local workspace="${TEST_TEMP}/workspace"

  mkdir -p "${workspace}/skills"
  run_discovery "${workspace}" skills "${TEST_TEMP}/output"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"no skills found"* ]]
}

@test "release tag defaults to empty and checkout follows the requested release" {
  local attach_condition
  local release_tag_env

  [ "$(yq -r '.on.workflow_call.inputs."release-tag".type' "${WORKFLOW}")" = 'string' ]
  [ "$(yq -r '.on.workflow_call.inputs."release-tag".default' "${WORKFLOW}")" = '' ]
  attach_condition="$(yq -r '.jobs."attach-to-release".if' "${WORKFLOW}")"
  [ "${attach_condition}" = "github.event_name == 'release' || inputs.release-tag != ''" ]
  release_tag_env="$(yq -r '.jobs."attach-to-release".steps[] | select(.name == "Attach packaged skills to the release") | .env.RELEASE_TAG' "${WORKFLOW}")"
  [ "${release_tag_env}" = "${{ inputs.release-tag || github.event.release.tag_name }}" ]
  [ "$(yq -r '.jobs.discover.steps[] | select(.name == "Checkout repository") | .with.ref' "${WORKFLOW}")" = "${{ inputs.release-tag || github.sha }}" ]
  [ "$(yq -r '.jobs.package.steps[] | select(.name == "Checkout repository") | .with.ref' "${WORKFLOW}")" = "${{ inputs.release-tag || github.sha }}" ]
}

@test "uploads one Actions artifact per skill and merges only for release attachments" {
  [ "$(yq -r '.jobs.package.strategy.matrix.skill' "${WORKFLOW}")" = "${{ fromJSON(needs.discover.outputs.skills) }}" ]
  [ "$(yq -r '.jobs.package.steps[] | select(.name == "Upload skill ZIP") | .with.name' "${WORKFLOW}")" = "${{ format('{0}-{1}', inputs.artifact-name, matrix.skill) }}" ]
  [ "$(yq -r '.jobs.package.steps[] | select(.name == "Upload skill ZIP") | .with.path' "${WORKFLOW}")" = "${{ runner.temp }}/agent-skill-packages/${{ matrix.skill }}.zip" ]
  [ "$(yq -r '.jobs."attach-to-release".steps[] | select(.name == "Download packaged skills") | .with.pattern' "${WORKFLOW}")" = "${{ format('{0}-*', inputs.artifact-name) }}" ]
  [ "$(yq -r '.jobs."attach-to-release".steps[] | select(.name == "Download packaged skills") | .with."merge-multiple"' "${WORKFLOW}")" = 'true' ]
  [ "$(yq -r '.on.workflow_call.outputs."artifact-names".value' "${WORKFLOW}")" = "${{ jobs.discover.outputs.artifact-names }}" ]
}

@test "release attachment uploads multiple individual ZIP assets using the selected tag" {
  local attach_script="${TEST_TEMP}/attach-skills.sh"
  local bin_dir="${TEST_TEMP}/bin"
  local runner_temp="${TEST_TEMP}/runner"

  yq -r '.jobs."attach-to-release".steps[] | select(.name == "Attach packaged skills to the release") | .run' "${WORKFLOW}" > "${attach_script}"
  mkdir -p "${bin_dir}" "${runner_temp}/agent-skill-release-assets"
  touch "${runner_temp}/agent-skill-release-assets/alpha.zip"
  touch "${runner_temp}/agent-skill-release-assets/beta.zip"
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
  [ "$(sed -n '5p' "${runner_temp}/gh-args")" = "${runner_temp}/agent-skill-release-assets/beta.zip" ]
  [ "$(sed -n '6p' "${runner_temp}/gh-args")" = '--repo' ]
  [ "$(sed -n '7p' "${runner_temp}/gh-args")" = 'dceoy/example' ]
  [ "$(sed -n '8p' "${runner_temp}/gh-args")" = '--clobber' ]
}
