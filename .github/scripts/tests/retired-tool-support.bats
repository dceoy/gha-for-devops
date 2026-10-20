#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
}

@test "Retired tool support is absent from reusable workflows" {
  local workflow
  for workflow in \
    typescript-package-lint-and-scan \
    typescript-package-format-and-pr \
    html-lint-and-scan \
    python-package-lint-and-scan \
    python-package-format-and-pr \
    python-package-test \
    python-package-mkdocs-gh-deploy \
    python-package-release-on-pypi-and-github \
    python-pyinstaller; do
    run ! grep -Eiq 'eslint|prettier|poetry|flake8|mypy|bandit|black|isort' "${REPO_ROOT}/.github/workflows/${workflow}.yml"
  done
}

@test "Oxfmt is the default HTML formatter" {
  local workflow="${REPO_ROOT}/.github/workflows/html-lint-and-scan.yml"
  [ "$(yq -r '.on.workflow_call.inputs."use-oxfmt".default' "${workflow}")" = true ]
  grep -Fq 'oxfmt --check' "${workflow}"
}

@test "Local QA has no ESLint or Poetry fallback" {
  local script="${REPO_ROOT}/.agents/skills/local-qa/scripts/qa.sh"
  run ! grep -Eq 'eslint|poetry' "${script}"
  grep -Fq 'pnpm exec oxlint --fix' "${script}"
}

@test "Python type checking optionally supports ty with uv and requirements installations" {
  local workflow="${REPO_ROOT}/.github/workflows/python-package-lint-and-scan.yml"
  [ "$(yq -r '.on.workflow_call.inputs."use-ty".default' "${workflow}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."use-pyright".default' "${workflow}")" = true ]
  # shellcheck disable=SC2016
  [ "$(grep -Fc 'USE_TY: ${{ inputs.use-ty }}' "${workflow}")" -eq 2 ]
  # shellcheck disable=SC2016
  [ "$(grep -Fc '[[ "${USE_TY}" == "true" ]] && packages+=(ty)' "${workflow}")" -eq 2 ]
  grep -Fq 'if: inputs.use-ty' "${workflow}"
  grep -Fq 'uv run ty check .' "${workflow}"
  grep -Fq 'ty check .' "${workflow}"
}
