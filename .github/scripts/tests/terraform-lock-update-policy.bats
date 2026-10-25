#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/terraform-lock-files-upgrade-and-pr-merge.yml"
  UPGRADE="${REPO_ROOT}/.github/workflows/terraform-lock-files-upgrade.yml"
}

@test "Terraform dependency PRs do not aggregate other PR branches" {
  [ "$(yq -r '.jobs."terraform-lock-pr-branch-merge" // "absent"' "${WORKFLOW}")" = absent ]
  [ "$(yq -r '.on.workflow_call.inputs."merged-pr-branch-prefix".default' "${WORKFLOW}")" = null ]
  [ "$(yq -r '.on.workflow_call.inputs."merge-pr-head-branch-prefix".default' "${WORKFLOW}")" = dependabot/terraform/ ]
  [ "$(yq -r '.on.workflow_call.inputs."merge-pr-author-allowlist".default' "${WORKFLOW}")" = 'dependabot[bot]' ]
}

@test "Terraform dependency PRs verify trusted Dependabot configuration and diff" {
  local check
  check="$(yq -r '.jobs."terraform-lock-pr-check".steps[] | select(.id == "validate-changes") | .run' "${WORKFLOW}")"
  [[ "${check}" == *'.github/dependabot.yml'* ]]
  [[ "${check}" == *'"package-ecosystem"] == "terraform"'* ]]
  [[ "${check}" == *'Unexpected Terraform dependency PR file'* ]]
  [[ "${check}" == *'lockfile-only=true'* ]]
  local config_step
  config_step="$(yq -r '.jobs."terraform-lock-pr-check".steps[] | select(.name == "Read the trusted base branch Dependabot configuration") | .run' "${WORKFLOW}")"
  [[ "${config_step}" == *'gh api "repos/${GITHUB_REPOSITORY}/contents/.github/dependabot.yml?ref=${PR_BASE_SHA}"'* ]]
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
  [[ "${guard}" == *'version-update:semver-patch'* ]]
  [[ "${guard}" == *'version-update:semver-minor'* ]]
  [[ "${merge}" == *'--auto'* ]]
  [[ "${merge}" == *'--match-head-commit'* ]]
  [[ "${merge}" != *'--admin'* ]]
}
