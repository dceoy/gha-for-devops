#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/terraform-dependabot-lock-upgrade-and-merge.yml"
  UPGRADE="${REPO_ROOT}/.github/workflows/terraform-lock-files-upgrade.yml"
}

@test "Terraform dependency PRs do not aggregate other PR branches" {
  [ "$(yq -r '.jobs."terraform-lock-pr-branch-merge" // "absent"' "${WORKFLOW}")" = absent ]
  [ "$(yq -r '.on.workflow_call.inputs | has("merged-pr-branch-prefix")' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs | has("merge-pr-head-branch-prefix")' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs | has("merge-pr-author-allowlist")' "${WORKFLOW}")" = false ]
}

@test "Terraform dependency PRs check provenance, metadata and lockfile-only status" {
  local identity metadata check
  identity="$(yq -r '.jobs."terraform-lock-pr-check".steps[] | select(.name == "Verify the Dependabot Terraform pull request") | .run' "${WORKFLOW}")"
  metadata="$(yq -r '.jobs."terraform-lock-pr-check".steps[] | select(.id == "dependabot-metadata") | .uses' "${WORKFLOW}")"
  check="$(yq -r '.jobs."terraform-lock-pr-check".steps[] | select(.id == "validate-changes") | .run' "${WORKFLOW}")"
  [ "$(yq -r '.jobs."terraform-lock-pr-check".steps | length' "${WORKFLOW}")" = 3 ]
  [[ "${identity}" == *'dependabot[bot]'* ]]
  [[ "${identity}" == *'dependabot/terraform/'* ]]
  [[ "${identity}" == *'PR_HEAD_REPOSITORY'* ]]
  [[ "${metadata}" == dependabot/fetch-metadata@* ]]
  [[ "${check}" == *'PACKAGE_ECOSYSTEM'* ]]
  [[ "${check}" == *'terraform'* ]]
  [[ "${check}" == *'gh pr diff'* ]]
  [[ "${check}" == *'lockfile-only=true'* ]]
}

@test "Already updated lockfile PRs do not upgrade all Terraform providers" {
  [ "$(yq -r '.on.workflow_call.inputs."upgrade-providers".default' "${UPGRADE}")" = true ]
  local flag
  flag="$(yq -r '.jobs."terraform-lock-files-upgrade".steps[] | select(.name == "Upgrade and validate Terraform lock files") | .run' "${UPGRADE}")"
  [[ "${flag}" == *'init_flags=(-upgrade)'* ]]
  [[ "${flag}" == *'init_flags=(-lockfile=readonly)'* ]]
  [ "$(yq -r '.jobs."terraform-lock-pr-upgrade".with."upgrade-providers"' "${WORKFLOW}")" = '$''{{ github.event_name != '"'"'pull_request'"'"' || needs.terraform-lock-pr-check.outputs.lockfile-only != '"'"'true'"'"' }}' ]
}

@test "Terraform dependency PR auto-merge checks metadata and current head" {
  local guard merge
  guard="$(yq -r '.jobs."terraform-lock-pr-merge".if' "${WORKFLOW}")"
  merge="$(yq -r '.jobs."terraform-lock-pr-merge".steps[] | select(.name == "Enable auto-merge after required checks and reviews") | .run' "${WORKFLOW}")"
  [[ "${guard}" == *"dependabot[bot]"* ]]
  [[ "${guard}" == *"dependabot/terraform/"* ]]
  [[ "${guard}" == *'version-update:semver-patch'* ]]
  [[ "${guard}" == *'version-update:semver-minor'* ]]
  [[ "${merge}" == *'--auto'* ]]
  [[ "${merge}" == *'--match-head-commit'* ]]
  [[ "${merge}" != *'--admin'* ]]
}
