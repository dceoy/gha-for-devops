#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  WORKFLOWS="$(cd "${BATS_TEST_DIRNAME}/../../workflows" && pwd)"
}

@test "maintenance dispatches the combined dependency updater" {
  local workflow="${WORKFLOWS}/maintenance.yml"
  run yq -r '.on.workflow_dispatch.inputs.task.options[]' "${workflow}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"dependencies-upgrade"* ]]

  run yq -r '.jobs."dependency-lock-update".uses' "${workflow}"
  [ "${status}" -eq 0 ]
  [ "${output}" = '$/.github/workflows/dependency-lock-update.yml' ]

  run yq -r '.jobs."github-release".if' "${workflow}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"inputs.task != 'dependencies-upgrade'"* ]]
}

@test "combined updater updates all lockfiles without modifying manifests" {
  local workflow="${WORKFLOWS}/dependency-lock-update.yml"
  run yq -r '.jobs."dependency-lock-update".steps[] | select(.run != null) | .run' "${workflow}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'mise lock --bump'* ]]
  [[ "${output}" == *'pnpm up --latest --lockfile-only --no-save'* ]]
  [[ "${output}" == *'uv lock --upgrade'* ]]
  run yq -r '.jobs."dependency-lock-update".steps[] | select(.uses != null and (.uses | test("peter-evans/create-pull-request@"))) | .with.branch' "${workflow}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}
