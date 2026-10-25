#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/terraform-dependabot-lock-upgrade-and-merge.yml"
  UPGRADE="${REPO_ROOT}/.github/workflows/terraform-lock-files-upgrade.yml"
  LINT="${REPO_ROOT}/.github/workflows/terraform-lint-and-scan.yml"
}

@test "Dependabot workflow does not aggregate branches or retain old overrides" {
  [ "$(yq -r '.jobs."terraform-lock-pr-branch-merge" // "absent"' "${WORKFLOW}")" = absent ]
  [ "$(yq -r '.on.workflow_call.inputs | has("merged-pr-branch-prefix")' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs | has("merge-pr-head-branch-prefix")' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs | has("merge-pr-author-allowlist")' "${WORKFLOW}")" = false ]
}

@test "Dependabot PR provenance, Terraform ecosystem and changed files are verified" {
  local identity metadata check
  identity="$(yq -r '.jobs."terraform-lock-pr-check".steps[] | select(.name == "Verify the Dependabot Terraform pull request") | .run' "${WORKFLOW}")"
  metadata="$(yq -r '.jobs."terraform-lock-pr-check".steps[] | select(.id == "dependabot-metadata") | .uses' "${WORKFLOW}")"
  check="$(yq -r '.jobs."terraform-lock-pr-check".steps[] | select(.name == "Verify Terraform dependency PR files") | .run' "${WORKFLOW}")"
  [ "$(yq -r '.jobs."terraform-lock-pr-check".steps | length' "${WORKFLOW}")" = 3 ]
  [[ "${identity}" == *'dependabot[bot]'* ]]
  [[ "${identity}" == *'dependabot/terraform/'* ]]
  [[ "${identity}" == *'PR_HEAD_REPOSITORY'* ]]
  [[ "${metadata}" == dependabot/fetch-metadata@* ]]
  [[ "${check}" == *'PACKAGE_ECOSYSTEM'* ]]
  [[ "${check}" == *'gh pr diff'* ]]
  [[ "${check}" == *'terragrunt'* ]]
  [[ "${check}" == *'terraform'* ]]
}

@test "Dependabot PRs are read-only and dispatch can still upgrade lockfiles" {
  [ "$(yq -r '.jobs."terraform-lock-pr-upgrade".if' "${WORKFLOW}")" = "github.event_name != 'pull_request'" ]
  [ "$(yq -r '.jobs."terraform-lock-pr-lint".with."terraform-lockfile-readonly"' "${WORKFLOW}")" = '$''{{ github.event_name == '"'"'pull_request'"'"' }}' ]
  [ "$(yq -r '.on.workflow_call.inputs."terraform-lockfile-readonly".default' "${LINT}")" = false ]
  [ "$(yq -r '.jobs."terraform-lint-and-scan".steps[] | select(.name == "Validate the code using terraform validate") | .run' "${LINT}")" != null ]
  local flag
  flag="$(yq -r '.jobs."terraform-lint-and-scan".steps[] | select(.name == "Validate the code using terraform validate") | .run' "${LINT}")"
  [[ "${flag}" == *'-lockfile=readonly'* ]]
  [ "$(yq -r '.on.workflow_call.inputs."upgrade-providers".default' "${UPGRADE}")" = true ]
}

@test "Auto-merge requires patch/minor metadata and the event head SHA" {
  local guard verify merge
  guard="$(yq -r '.jobs."terraform-lock-pr-merge".if' "${WORKFLOW}")"
  verify="$(yq -r '.jobs."terraform-lock-pr-merge".steps[] | select(.name == "Verify the current pull request and checks") | .run' "${WORKFLOW}")"
  merge="$(yq -r '.jobs."terraform-lock-pr-merge".steps[] | select(.name == "Enable auto-merge after required checks and reviews") | .run' "${WORKFLOW}")"
  [[ "${guard}" == *"dependabot[bot]"* ]]
  [[ "${guard}" == *"dependabot/terraform/"* ]]
  [[ "${guard}" == *'version-update:semver-patch'* ]]
  [[ "${guard}" == *'version-update:semver-minor'* ]]
  [[ "${verify}" == *'PR_HEAD_SHA'* ]]
  [[ "${verify}" == *'headRefOid'* ]]
  [[ "${merge}" == *'--auto'* ]]
  [[ "${merge}" == *'--match-head-commit'* ]]
  [[ "${merge}" != *'--admin'* ]]
}
