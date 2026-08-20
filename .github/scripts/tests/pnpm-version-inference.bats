#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  FIXTURES="${REPO_ROOT}/.github/fixtures/pnpm"
  WORKFLOWS=(
    bats-test.yml
    html-lint-and-scan.yml
    typescript-package-format-and-pr.yml
    typescript-package-lint-and-scan.yml
    typescript-package-script.yml
  )
}

pnpm_step_value() {
  local workflow="$1"
  local key="$2"

  yq -r ".jobs.*.steps[] | select(.uses | test(\"^pnpm/action-setup@\")) | .with.\"${key}\"" \
    "${REPO_ROOT}/.github/workflows/${workflow}"
}

@test "every pnpm setup workflow defaults to repository version inference" {
  for workflow in "${WORKFLOWS[@]}"; do
    default_version="$(
      yq -r '.on.workflow_call.inputs."pnpm-version".default' \
        "${REPO_ROOT}/.github/workflows/${workflow}"
    )"
    [ -z "${default_version}" ]
    # shellcheck disable=SC2016
    [ "$(pnpm_step_value "${workflow}" version)" = '${{ inputs.pnpm-version || env.PNPM_VERSION }}' ]
  done
}

@test "root and nested workflows resolve package.json relative to the repository root" {
  root_package_manager="$(yq -r .packageManager "${FIXTURES}/root/package.json")"
  nested_package_manager="$(yq -r .packageManager "${FIXTURES}/nested/apps/site/package.json")"
  [[ "${root_package_manager}" =~ ^pnpm@[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [ "${nested_package_manager}" = "${root_package_manager}" ]

  [ "$(pnpm_step_value bats-test.yml package_json_file)" = "package.json" ]
  for workflow in \
    html-lint-and-scan.yml \
    typescript-package-format-and-pr.yml \
    typescript-package-lint-and-scan.yml \
    typescript-package-script.yml; do
    [ "$(pnpm_step_value "${workflow}" package_json_file)" = "\${{ format('{0}/package.json', inputs.package-path) }}" ]
  done
}
