#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
}

@test "Dependabot and Renovate do not auto-merge Python dependency updates" {
  local ci="${REPO_ROOT}/.github/workflows/ci.yml"
  local reusable="${REPO_ROOT}/.github/workflows/dependabot-auto-merge.yml"
  local renovate="${REPO_ROOT}/.github/renovate.json"
  local approve_if

  [ "$(yq -r '.jobs."dependabot-auto-merge".with."allow-python-dependency-auto-merge"' "${ci}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."allow-python-dependency-auto-merge".default' "${reusable}")" = true ]

  approve_if="$(yq -r '.jobs."dependabot-auto-merge".steps[] | select(.id == "approve-pr") | .if' "${reusable}")"
  [[ "${approve_if}" == *"steps.metadata.outputs.package-ecosystem != 'uv'"* ]]
  [[ "${approve_if}" == *"steps.metadata.outputs.package-ecosystem != 'pip'"* ]]

  jq -e 'any(.packageRules[]; .automerge == false and
    ((.matchManagers // []) == ["pep621"]))' "${renovate}" > /dev/null
}
