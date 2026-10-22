#!/usr/bin/env bats
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  SCAN="$REPO_ROOT/.github/workflows/syft-grype-scan.yml"
}

@test "Syft and Grype use one inventory with read-only permissions" {
  [ "$(yq -r '.permissions.contents' "$SCAN")" = read ]
  [ "$(yq -r '.jobs."syft-grype-scan".permissions.contents' "$SCAN")" = read ]
  [ "$(yq -r '.jobs."syft-grype-scan".strategy."fail-fast"' "$SCAN")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."grype-fail-on".default' "$SCAN")" = high ]
  [ "$(yq -r '.on.workflow_call.inputs."grype-only-fixed".default' "$SCAN")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."sbom-artifact-name".default' "$SCAN")" = null ]
  [ "$(yq -r '[.jobs."syft-grype-scan".steps[] | select(.name == "Generate Syft SBOM")] | length' "$SCAN")" = 1 ]
  [ "$(yq -r '[.jobs."syft-grype-scan".steps[] | select(.name == "Scan SBOM with Grype")] | length' "$SCAN")" = 1 ]
  grep -Fq 'syft-json=' "$SCAN"
  grep -Fq 'cyclonedx-json=' "$SCAN"
  grep -Fq '"sbom:${SBOM}"' "$SCAN"
}

@test "Existing security and Docker workflows keep Grype optional" {
  for name in source-security-scan container-security docker-lint-and-scan docker-build-and-push docker-buildx-bake docker-build-with-multi-targets docker-pull-from-aws docker-save-and-terraform-deploy-to-aws; do
    workflow="$REPO_ROOT/.github/workflows/$name.yml"
    [ "$(yq -r '.on.workflow_call.inputs."use-syft-grype".default' "$workflow")" = false ]
    [ "$(yq -r '.on.workflow_call.inputs."grype-only-fixed".default' "$workflow")" = true ]
  done
  [ "$(yq -r '.jobs."source-syft-grype-scan".uses' "$REPO_ROOT/.github/workflows/source-security-scan.yml")" = '$/.github/workflows/syft-grype-scan.yml' ]
  [ "$(yq -r '.jobs."container-syft-grype-scan".uses' "$REPO_ROOT/.github/workflows/container-security.yml")" = '$/.github/workflows/syft-grype-scan.yml' ]
}

@test "Build and Bake security jobs depend on completed image builds" {
  [ "$(yq -r '.jobs."docker-postbuild-syft-grype".needs' "$REPO_ROOT/.github/workflows/docker-build-and-push.yml")" = docker-build-and-push ]
  [ "$(yq -r '.jobs."docker-bake-postbuild-syft-grype".needs' "$REPO_ROOT/.github/workflows/docker-buildx-bake.yml")" = docker-buildx-bake ]
}
