#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  TRIVY="$REPO_ROOT/.github/workflows/trivy-scan.yml"
  CORE="$REPO_ROOT/.github/workflows/trivy-core.yml"
  SOURCE="$REPO_ROOT/.github/workflows/source-security-scan.yml"
  CONTAINER="$REPO_ROOT/.github/workflows/container-security.yml"
  PUBLISH_SCRIPT="$BATS_TEST_TMPDIR/publish.sh"
  yq -r '.jobs.submit.steps[] | select(.name == "Validate and publish dependency snapshot") | .run' "$TRIVY" > "$PUBLISH_SCRIPT"
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary"
}

@test "Trivy core scans all categories once and converts reports" {
  [ "$(yq -r '[.jobs.scan.steps[] | select(.uses | contains("aquasecurity/trivy-action@"))] | length' "$CORE")" = 1 ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.name == "Scan once with all requested scanners") | .with.format' "$CORE")" = json ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.name == "Scan once with all requested scanners") | .with."list-all-pkgs"' "$CORE")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."trivy-scanners".default' "$CORE")" = 'vuln,secret,misconfig' ]
  grep -Fq 'trivy convert --format github' "$CORE"
  grep -Fq 'trivy convert --format "$REPORT_FORMAT"' "$CORE"
}

@test "Only the integrated publisher is writable and gated to trusted events" {
  [ "$(yq -r '.jobs.scan.permissions.contents' "$TRIVY")" = read ]
  [ "$(yq -r '.jobs.submit.permissions.contents' "$TRIVY")" = write ]
  [ "$(yq -r '.jobs.scan.permissions.contents' "$CORE")" = read ]
  [ "$(yq -r '.permissions.contents' "$SOURCE")" = read ]
  [ "$(yq -r '.permissions.contents' "$CONTAINER")" = read ]
  [ "$(yq -r '.jobs."trivy-scan".uses' "$SOURCE")" = './.github/workflows/trivy-core.yml' ]
  [ "$(yq -r '.jobs.scan.uses' "$CONTAINER")" = './.github/workflows/trivy-core.yml' ]
  [ ! -e "$REPO_ROOT/.github/workflows/dependency-submission.yml" ]
  local cond
  cond="$(yq -r '.jobs.submit.if' "$TRIVY")"
  [[ "$cond" == *"inputs.submit-dependencies"* ]]
  [[ "$cond" == *"github.event_name == 'push'"* ]]
  [[ "$cond" == *"github.event_name == 'schedule'"* ]]
  [[ "$cond" == *"github.event_name == 'workflow_dispatch'"* ]]
  [[ "$cond" == *"github.event.repository.default_branch"* ]]
}

@test "Publisher validates snapshots and propagates HTTP errors" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/curl" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CURL_ARGS"
exit "$CURL_STATUS"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CURL_ARGS="$BATS_TEST_TMPDIR/curl-args"
  export SNAPSHOT="$BATS_TEST_TMPDIR/snapshot.json"
  printf '%s\n' '{"version":0,"detector":{"name":"trivy"},"job":{"correlator":"stable-image-target"},"manifests":{}}' > "$SNAPSHOT"
  local code
  for code in 0 22 7; do
    : > "$GITHUB_STEP_SUMMARY"
    run env CURL_STATUS="$code" GH_TOKEN=test-token GITHUB_API_URL=https://api.github.com GITHUB_REPOSITORY=owner/repo bash "$PUBLISH_SCRIPT"
    [ "$status" -eq "$code" ]
    grep -Fxq -- '--fail-with-body' "$CURL_ARGS"
    grep -Fxq -- '--data-binary' "$CURL_ARGS"
    grep -Fxq -- "@$SNAPSHOT" "$CURL_ARGS"
    grep -Fxq -- 'Authorization: Bearer test-token' "$CURL_ARGS"
  done
  printf '%s\n' '{"version":0,"detector":{"name":"trivy"},"job":{"correlator":""},"manifests":{}}' > "$SNAPSHOT"
  rm -f "$CURL_ARGS"
  run env CURL_STATUS=0 GH_TOKEN=test-token GITHUB_API_URL=https://api.github.com GITHUB_REPOSITORY=owner/repo bash "$PUBLISH_SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -e "$CURL_ARGS" ]
}

@test "Stable correlator is injected into each converted snapshot" {
  [ "$(yq -r '.jobs.scan.with."snapshot-correlator"' "$TRIVY")" = '${{ inputs.snapshot-correlator }}' ]
  grep -Fq 'jq -e --arg correlator "$SNAPSHOT_CORRELATOR"' "$CORE"
  grep -Fq '.job.correlator=$correlator' "$CORE"
}

@test "Table summary omits matching secret values" {
  local script
  script="$BATS_TEST_TMPDIR/report.sh"
  yq -r '.jobs.scan.steps[] | select(.name == "Convert report from JSON") | .run' "$CORE" > "$script"
  export REPORT_FORMAT=table RAW_REPORT="$BATS_TEST_TMPDIR/trivy.json" REPORT="$BATS_TEST_TMPDIR/report.txt"
  printf '%s\n' '{"Results":[{"Target":"SECRET_PATH","Secrets":[{"Title":"SECRET_SENTINEL"}],"Vulnerabilities":[{"VulnerabilityID":"CVE-1"}]}]}' > "$RAW_REPORT"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/trivy" << 'SH'
#!/usr/bin/env bash
printf '%s\n' SECRET_SENTINEL > "$REPORT"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/trivy"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  run bash "$script"
  [ "$status" -eq 0 ]
  grep -Fq 'Vulnerabilities: 1' "$GITHUB_STEP_SUMMARY"
  grep -Fq 'Secrets: 1' "$GITHUB_STEP_SUMMARY"
  run ! grep -Fq SECRET_SENTINEL "$GITHUB_STEP_SUMMARY"
}

@test "Security wrappers keep Semgrep within the selected package" {
  local wrapper
  for wrapper in security-pr security-audit; do
    # shellcheck disable=SC2016
    [ "$(yq -r '.jobs.source.with."semgrep-working-directory"' "${REPO_ROOT}/.github/workflows/${wrapper}.yml")" = '${{ inputs.package-path }}' ]
  done
}

@test "Security PR history uses full mode for branch-creation pushes" {
  # shellcheck disable=SC2016
  [ "$(yq -r '.jobs.history.with."scan-mode"' "${REPO_ROOT}/.github/workflows/security-pr.yml")" = '${{ github.event_name == '\''push'\'' && github.event.created && '\''full'\'' || '\''range'\'' }}' ]
  yq -r '.jobs.trufflehog.steps[] | select(.id == "range") | .run' "${REPO_ROOT}/.github/workflows/git-secret-scan.yml" > "${BATS_TEST_TMPDIR}/range.sh"
  cd "${REPO_ROOT}"
  run env SCAN_MODE=full BASE_INPUT= PR_BASE= PUSH_BEFORE=0000000000000000000000000000000000000000 GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/range-output" bash "${BATS_TEST_TMPDIR}/range.sh"
  [ "${status}" -eq 0 ]
  grep -Fxq 'skip=false' "${BATS_TEST_TMPDIR}/range-output"
}
