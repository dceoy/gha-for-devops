#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOWS=(
    python-package-lint-and-scan.yml
    typescript-package-lint-and-scan.yml
    go-package-lint-and-scan.yml
    shell-lint.yml
    github-actions-lint-and-scan.yml
    terraform-lint-and-scan.yml
    docker-lint-and-scan.yml
    html-lint-and-scan.yml
  )
}

@test "Supported lint and scan workflows expose optional Semgrep and enforce findings" {
  for workflow in "${WORKFLOWS[@]}"; do
    file="${REPO_ROOT}/.github/workflows/${workflow}"
    [[ "$(yq -r '.on.workflow_call.inputs."use-semgrep".default' "${file}")" == true ]]
    grep -Fq 'if: inputs.use-semgrep' "${file}"
    grep -Fq 'semgrep scan \' "${file}"
    grep -Fq -- '--config p/default --metrics off --error' "${file}"
  done
}

@test "Local QA runs one pinned Semgrep scan with no cloud credentials" {
  file="${REPO_ROOT}/.agents/skills/local-qa/scripts/qa.sh"
  [[ "$(grep -c 'semgrep scan --config p/default' "${file}")" -eq 1 ]]
  grep -Fq 'uvx --from "semgrep==${SEMGREP_VERSION}"' "${file}"
  bash -n "${file}"
}
