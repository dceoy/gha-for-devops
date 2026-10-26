#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
}

@test "Dependabot approval follows unconditional or safe update" {
  local ci="${REPO_ROOT}/.github/workflows/ci.yml"
  local reusable="${REPO_ROOT}/.github/workflows/dependabot-auto-merge.yml"
  local approve_if

  [ "$(yq -r '.jobs."dependabot-auto-merge".with.unconditional' "${ci}")" = true ]

  approve_if="$(yq -r '.jobs."dependabot-auto-merge".steps[] | select(.id == "approve-pr") | .if' "${reusable}")"
  [ "${approve_if}" = "inputs.unconditional || steps.safe-update.outputs.safe == 'true'" ]
}
