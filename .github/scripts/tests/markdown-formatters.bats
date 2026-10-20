#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
}

@test "Markdown workflows default to Oxfmt and do not invoke Prettier" {
  for workflow in markdown-lint.yml markdown-format-and-pr.yml; do
    file="${REPO_ROOT}/.github/workflows/${workflow}"
    [ "$(yq -r '.on.workflow_call.inputs."use-oxfmt".default' "${file}")" = true ]
    [ "$(yq -r '.on.workflow_call.inputs | has("use-prettier")' "${file}")" = false ]
    ! grep -qi 'prettier' "${file}"
    grep -Fq 'if: inputs.use-oxfmt && inputs.use-biome' "${file}"
  done
}

@test "TypeScript Oxfmt CI fails on an unmatched glob" {
  file="${REPO_ROOT}/.github/workflows/typescript-package-lint-and-scan.yml"
  grep -Fq 'oxfmt --check "${OXFMT_GLOB}"' "${file}"
  ! grep -Fq 'oxfmt --check --no-error-on-unmatched-pattern' "${file}"
}
