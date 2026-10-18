#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  TRIVY="$REPO_ROOT/.github/workflows/trivy-scan.yml"
  SOURCE="$REPO_ROOT/.github/workflows/source-security-scan.yml"
  CONTAINER="$REPO_ROOT/.github/workflows/container-security.yml"
  PUBLISH_SCRIPT="$BATS_TEST_TMPDIR/publish.sh"
  yq -r '.jobs.submit.steps[] | select(.name == "Validate and publish dependency snapshot") | .run' "$TRIVY" > "$PUBLISH_SCRIPT"
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary"
}

@test "Trivy scan runs each category once and converts reports" {
  [ "$(yq -r '[.jobs.scan.steps[] | select(.uses | contains("aquasecurity/trivy-action@"))] | length' "$TRIVY")" = 1 ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.name == "Scan once with all requested scanners") | .with.format' "$TRIVY")" = json ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.name == "Scan once with all requested scanners") | .with."list-all-pkgs"' "$TRIVY")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."trivy-scanners".default' "$TRIVY")" = 'vuln,secret,misconfig' ]
  grep -Fq 'trivy convert --format github' "$TRIVY"
  grep -Fq 'trivy convert --scanners "${TRIVY_SCANNERS}" --format "${REPORT_FORMAT}"' "$TRIVY"
}

@test "Only the integrated publisher is writable and gated to trusted events" {
  [ "$(yq -r '.jobs.scan.permissions.contents' "$TRIVY")" = read ]
  [ "$(yq -r '.jobs.submit.permissions.contents' "$TRIVY")" = null ]
  [ "$(yq -r '.jobs.scan.permissions.contents' "$TRIVY")" = read ]
  [ "$(yq -r '.permissions.contents' "$SOURCE")" = read ]
  [ "$(yq -r '.permissions.contents' "$CONTAINER")" = read ]
  [ "$(yq -r '.jobs.scan.permissions | keys | join(",")' "$CONTAINER")" = contents ]
  [ "$(yq -r '.jobs."trivy-scan".uses' "$SOURCE")" = '$/.github/workflows/trivy-scan.yml' ]
  [ "$(yq -r '.jobs.scan.uses' "$CONTAINER")" = '$/.github/workflows/trivy-scan.yml' ]
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
  [ "$(yq -r '.jobs.prepare.steps[] | select(.id == "targets") | .env.CORRELATOR' "$TRIVY")" = '${{ inputs.snapshot-correlator }}' ]
  grep -Fq 'jq -e --arg correlator "${SNAPSHOT_CORRELATOR}"' "$TRIVY"
  grep -Fq '.job.correlator=$correlator' "$TRIVY"
}

@test "Conversions retain requested findings despite repository severity and exit settings" {
  export RAW_REPORT="$BATS_TEST_TMPDIR/trivy.json"
  export REPORT="$BATS_TEST_TMPDIR/report"
  export SNAPSHOT="$BATS_TEST_TMPDIR/snapshot.json"
  export SNAPSHOT_CORRELATOR=source-root
  export TRIVY_SCANNERS=vuln TRIVY_SEVERITY=HIGH,CRITICAL
  cat > "$RAW_REPORT" << 'JSON'
{"SchemaVersion":2,"ArtifactName":"fixture","ArtifactType":"filesystem","Results":[{"Target":"package-lock.json","Class":"lang-pkgs","Type":"npm","Packages":[{"ID":"lodash@4.17.20","Name":"lodash","Version":"4.17.20"}],"Vulnerabilities":[{"VulnerabilityID":"CVE-2026-1234","PkgName":"lodash","PkgID":"lodash@4.17.20","InstalledVersion":"4.17.20","FixedVersion":"4.17.21","Severity":"HIGH","Title":"fixture vulnerability"}]}]}
JSON
  printf 'severity: [CRITICAL]\nexit-code: 23\n' > "$BATS_TEST_TMPDIR/trivy.yaml"
  yq -r '.jobs.scan.steps[] | select(.name == "Convert report from JSON") | .run' "$TRIVY" > "$BATS_TEST_TMPDIR/report.sh"
  yq -r '.jobs.scan.steps[] | select(.name == "Convert dependency snapshot without rescanning") | .run' "$TRIVY" > "$BATS_TEST_TMPDIR/snapshot.sh"
  cd "$BATS_TEST_TMPDIR"
  local format
  for format in table sarif; do
    run env REPORT_FORMAT="$format" bash "$BATS_TEST_TMPDIR/report.sh"
    [ "$status" -eq 0 ]
    grep -Fq CVE-2026-1234 "$REPORT"
  done
  run bash "$BATS_TEST_TMPDIR/snapshot.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.job.correlator' "$SNAPSHOT")" = source-root ]
  [ "$(jq -r '.manifests["package-lock.json"].resolved.lodash.package_url' "$SNAPSHOT")" = pkg:npm/lodash@4.17.20 ]
}

@test "Findings enforcement honors requested severity and exit code over repository config" {
  export RAW_REPORT="$BATS_TEST_TMPDIR/trivy.json"
  export TRIVY_SCANNERS=vuln TRIVY_SEVERITY=HIGH,CRITICAL
  printf '%s\n' '{"SchemaVersion":2,"ArtifactName":"fixture","ArtifactType":"filesystem","Results":[{"Target":"fixture","Class":"lang-pkgs","Type":"npm","Vulnerabilities":[{"VulnerabilityID":"CVE-2026-1234","PkgName":"lodash","InstalledVersion":"4.17.20","Severity":"HIGH"}]}]}' > "$RAW_REPORT"
  printf 'severity: [CRITICAL]\nexit-code: 23\n' > "$BATS_TEST_TMPDIR/trivy.yaml"
  yq -r '.jobs.scan.steps[] | select(.name == "Enforce findings policy") | .run' "$TRIVY" > "$BATS_TEST_TMPDIR/enforce.sh"
  cd "$BATS_TEST_TMPDIR"
  local code
  for code in 0 7; do
    run env EXIT_CODE="$code" bash "$BATS_TEST_TMPDIR/enforce.sh"
    [ "$status" -eq "$code" ]
  done
}

@test "Table summary omits matching secret values" {
  local script
  script="$BATS_TEST_TMPDIR/report.sh"
  yq -r '.jobs.scan.steps[] | select(.name == "Convert report from JSON") | .run' "$TRIVY" > "$script"
  export TRIVY_SEVERITY=HIGH,CRITICAL TRIVY_SCANNERS=vuln,secret,misconfig REPORT_FORMAT=table RAW_REPORT="$BATS_TEST_TMPDIR/trivy.json" REPORT="$BATS_TEST_TMPDIR/report.txt"
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
