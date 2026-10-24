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

@test "All scan output paths stay within the runner temporary directory" {
  paths="$(yq -o json '.jobs."syft-grype-scan".steps' "$SCAN" | jq -r ' .[] | (if (.uses // "" | test("^actions/(upload|download)-artifact@")) then (.with.path // "") else "" end), (.env.IMAGE_TAR // ""), (.env.SBOM // ""), (.env.CYCLONEDX // ""), (.env.REPORT // "") | select(. != "")')"
  [ "$(wc -l <<< "$paths")" -eq 9 ]
  while IFS= read -r path; do
    [[ "$path" == '${{ runner.temp }}/'* ]]
  done <<< "$paths"
}

@test "Scanner caches retain pinned binaries and refresh the vulnerability database" {
  [ "$(yq -r '.jobs."syft-grype-scan".steps[] | select(.name == "Cache pinned Syft and Grype installations") | .with.key' "$SCAN")" = 'syft-grype-tools-${{ runner.os }}-${{ runner.arch }}-${{ env.SYFT_VERSION }}-${{ env.GRYPE_VERSION }}' ]
  [ "$(yq -r '.jobs."syft-grype-scan".steps[] | select(.name == "Cache Grype vulnerability database") | .with.path' "$SCAN")" = '${{ runner.temp }}/grype-db' ]
  [ "$(yq -r '.jobs."syft-grype-scan".steps[] | select(.name == "Scan SBOM with Grype") | .env.GRYPE_DB_CACHE_DIR' "$SCAN")" = '${{ runner.temp }}/grype-db' ]
  [ "$(yq -r '.jobs."syft-grype-scan".env.GRYPE_DB_AUTO_UPDATE' "$SCAN")" = null ]
}

@test "Filesystem workflow executes real Syft and Grype and produces valid reports" {
  export RUNNER_TEMP="$BATS_TEST_TMPDIR/runner temp"
  mkdir -p "$RUNNER_TEMP" "$BATS_TEST_TMPDIR/source"
  printf '%s\n' 'scan-smoke-fixture==1.0.0' > "$BATS_TEST_TMPDIR/source/requirements.txt"
  export SYFT_BIN GRYPE_BIN
  SYFT_BIN="$(command -v syft)"
  GRYPE_BIN="$(command -v grype)"
  export SCAN_TYPE=filesystem SCAN_REF="$BATS_TEST_TMPDIR/source"
  export SYFT_CHECK_FOR_APP_UPDATE=false GRYPE_CHECK_FOR_APP_UPDATE=false
  export GITHUB_STEP_SUMMARY="$RUNNER_TEMP/summary" GITHUB_OUTPUT="$RUNNER_TEMP/output"
  export SBOM CYCLONEDX REPORT
  SBOM="$(yq -r '.jobs."syft-grype-scan".steps[] | select(.name == "Generate Syft SBOM") | .env.SBOM' "$SCAN")"
  CYCLONEDX="$(yq -r '.jobs."syft-grype-scan".steps[] | select(.name == "Generate Syft SBOM") | .env.CYCLONEDX' "$SCAN")"
  REPORT="$(yq -r '.jobs."syft-grype-scan".steps[] | select(.name == "Scan SBOM with Grype") | .env.REPORT' "$SCAN")"
  SBOM="${SBOM//'${{ runner.temp }}'/$RUNNER_TEMP}"
  CYCLONEDX="${CYCLONEDX//'${{ runner.temp }}'/$RUNNER_TEMP}"
  REPORT="${REPORT//'${{ runner.temp }}'/$RUNNER_TEMP}"
  bash -euo pipefail -c "$(yq -r '.jobs."syft-grype-scan".steps[] | select(.name == "Generate Syft SBOM") | .run' "$SCAN")"
  jq -e '.artifacts | any(.name == "scan-smoke-fixture")' "$SBOM"
  jq -e '.bomFormat == "CycloneDX"' "$CYCLONEDX"
  export FAIL_ON='' ONLY_FIXED=true
  bash -euo pipefail -c "$(yq -r '.jobs."syft-grype-scan".steps[] | select(.name == "Scan SBOM with Grype") | .run' "$SCAN")"
  jq -e '.matches | type == "array"' "$REPORT"
  grep -Fxq 'exit-code=0' "$GITHUB_OUTPUT"
  export EXIT_CODE=0
  bash -euo pipefail -c "$(yq -r '.jobs."syft-grype-scan".steps[] | select(.name == "Enforce Grype policy") | .run' "$SCAN")"
}
