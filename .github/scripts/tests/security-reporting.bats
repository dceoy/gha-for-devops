#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  SOURCE="${REPO_ROOT}/.github/workflows/source-security-scan.yml"
  SUBMISSION="${REPO_ROOT}/.github/workflows/dependency-submission.yml"
  yq -r '.jobs.scan.steps[] | select(.name == "Summarize Trivy findings") | .run' "${SOURCE}" > "${BATS_TEST_TMPDIR}/summary.sh"
  for id in validate publish; do
    yq -r ".jobs.submit.steps[] | select(.id == \"${id}\") | .run" "${SUBMISSION}" > "${BATS_TEST_TMPDIR}/${id}.sh"
  done
  export REPORT="${BATS_TEST_TMPDIR}/report.sarif"
  export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary"
}

@test "Trivy summary exposes rule locations without messages, snippets, or HTML injection" {
  cat > "${REPORT}" << 'JSON'
{"runs":[{"results":[{"ruleId":"CVE-2026-1234","level":"error","message":{"text":"SECRET_SENTINEL"},"locations":[{"physicalLocation":{"artifactLocation":{"uri":"package<unsafe>.lock"},"region":{"startLine":42,"snippet":{"text":"SECRET_SENTINEL"}}}}]},{"ruleId":"secret-rule","level":"warning","message":{"text":"SECRET_SENTINEL"}}]}]}
JSON
  run bash "${BATS_TEST_TMPDIR}/summary.sh"
  [ "${status}" -eq 0 ]
  grep -Fq 'Findings: 2' "${GITHUB_STEP_SUMMARY}"
  grep -Fq 'CVE-2026-1234' "${GITHUB_STEP_SUMMARY}"
  grep -Fq 'package&lt;unsafe&gt;.lock:42' "${GITHUB_STEP_SUMMARY}"
  grep -Fq 'secret-rule' "${GITHUB_STEP_SUMMARY}"
  run ! grep -Fq SECRET_SENTINEL "${GITHUB_STEP_SUMMARY}"
  run ! grep -Fq '<unsafe>' "${GITHUB_STEP_SUMMARY}"
}

@test "Trivy summary bounds both finding count and field lengths" {
  jq -n '{runs:[{results:[range(0;200) | {ruleId:("x" * 10000),level:("x" * 10000),locations:[{physicalLocation:{artifactLocation:{uri:("x" * 10000)},region:{startLine:1}}}]}]}]}' > "${REPORT}"
  run bash "${BATS_TEST_TMPDIR}/summary.sh"
  [ "${status}" -eq 0 ]
  grep -Fq 'Findings: 200' "${GITHUB_STEP_SUMMARY}"
  [ "$(grep -c '<tr><td>' "${GITHUB_STEP_SUMMARY}")" -eq 100 ]
  [ "$(wc -c < "${GITHUB_STEP_SUMMARY}")" -lt 100000 ]
}

@test "Trivy summary reports zero findings for an empty result set" {
  printf '%s\n' '{"runs":[{"results":[]}]}' > "${REPORT}"
  run bash "${BATS_TEST_TMPDIR}/summary.sh"
  [ "${status}" -eq 0 ]
  grep -Fq 'Findings: 0' "${GITHUB_STEP_SUMMARY}"
}

@test "Trivy summary handles unavailable or malformed reports without echoing them" {
  local report_data
  for report_data in '' 'SECRET_SENTINEL invalid JSON' '{"runs":null}'; do
    printf '%s' "${report_data}" > "${REPORT}"
    run bash "${BATS_TEST_TMPDIR}/summary.sh"
    [ "${status}" -eq 0 ]
    grep -Fq 'did not generate a valid SARIF report' "${GITHUB_STEP_SUMMARY}"
    run ! grep -Fq SECRET_SENTINEL "${GITHUB_STEP_SUMMARY}"
    : > "${GITHUB_STEP_SUMMARY}"
  done
}

@test "Dependency submission rejects untrusted events before accessing repository content" {
  [ "$(yq -r '.jobs.submit.steps[0].id' "${SUBMISSION}")" = validate ]
  local event
  for event in pull_request pull_request_target workflow_run; do
    run env EVENT_NAME="${event}" SCAN_TYPE=filesystem IMAGE_REF= IMAGE_ARTIFACT_NAME= SNAPSHOT_CORRELATOR=source bash "${BATS_TEST_TMPDIR}/validate.sh"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *'requires a trusted'* ]]
  done
}

@test "Dependency submission accepts trusted filesystem and image inventory requests" {
  local event scan_type image artifact
  while read -r event scan_type image artifact; do
    run env EVENT_NAME="${event}" SCAN_TYPE="${scan_type}" IMAGE_REF="${image//NONE/}" IMAGE_ARTIFACT_NAME="${artifact//NONE/}" SNAPSHOT_CORRELATOR=stable-target bash "${BATS_TEST_TMPDIR}/validate.sh"
    [ "${status}" -eq 0 ]
  done << 'CASES'
push filesystem NONE NONE
schedule image ghcr.io/example/app:latest NONE
workflow_dispatch image local-image:test image-tar
CASES
}

@test "Dependency submission rejects invalid target requests" {
  local scan_type image artifact correlator
  while read -r scan_type image artifact correlator; do
    run env EVENT_NAME=push SCAN_TYPE="${scan_type}" IMAGE_REF="${image//NONE/}" IMAGE_ARTIFACT_NAME="${artifact//NONE/}" SNAPSHOT_CORRELATOR="${correlator//NONE/}" bash "${BATS_TEST_TMPDIR}/validate.sh"
    [ "${status}" -eq 1 ]
  done << 'CASES'
unsupported NONE NONE source
image NONE NONE source
image local-image:test ../escape source
filesystem NONE image-tar source
filesystem NONE NONE NONE
CASES
}

@test "Dependency submission sends the snapshot and propagates HTTP and transport failures" {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/curl" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${CURL_ARGS}"
exit "${CURL_STATUS}"
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  export CURL_ARGS="${BATS_TEST_TMPDIR}/curl-args"
  export SNAPSHOT_FILE="${BATS_TEST_TMPDIR}/snapshot.json"
  export SNAPSHOT_CORRELATOR='stable-image-target'
  printf '%s\n' '{"version":0,"sha":"abc","job":{"correlator":"default"},"manifests":{}}' > "${SNAPSHOT_FILE}"
  local expected_status
  for expected_status in 0 22 7; do
    : > "${GITHUB_STEP_SUMMARY}"
    run env CURL_STATUS="${expected_status}" GH_TOKEN=test-token GITHUB_API_URL=https://api.github.com GITHUB_REPOSITORY=owner/repo bash "${BATS_TEST_TMPDIR}/publish.sh"
    [ "${status}" -eq "${expected_status}" ]
    [ "$(jq -r '.job.correlator' "${SNAPSHOT_FILE}.submit")" = stable-image-target ]
    [ "$(jq -r '.sha' "${SNAPSHOT_FILE}.submit")" = abc ]
    grep -Fxq -- '--fail' "${CURL_ARGS}"
    grep -Fxq -- '--data-binary' "${CURL_ARGS}"
    grep -Fxq -- "@${SNAPSHOT_FILE}.submit" "${CURL_ARGS}"
    grep -Fxq 'https://api.github.com/repos/owner/repo/dependency-graph/snapshots' "${CURL_ARGS}"
    grep -Fxq 'Authorization: Bearer test-token' "${CURL_ARGS}"
  done
  [ ! -s "${GITHUB_STEP_SUMMARY}" ]
}

@test "Only the separate dependency publication job requires write permission" {
  [ "$(yq -r '.jobs.submit.permissions.contents' "${SUBMISSION}")" = write ]
  [ "$(yq -r '.jobs.submit.steps[] | select(.name == "Generate dependency snapshot") | .with.format' "${SUBMISSION}")" = github ]
  [ "$(yq -r '.jobs.submit.steps[] | select(.name == "Generate dependency snapshot") | .with."list-all-pkgs"' "${SUBMISSION}")" = true ]
  local workflow
  for workflow in source-security-scan container-security docker-lint-and-scan terraform-lint-and-scan security-pr; do
    [ "$(yq -r '.permissions.contents' "${REPO_ROOT}/.github/workflows/${workflow}.yml")" = read ]
    run ! grep -Fq 'contents: write' "${REPO_ROOT}/.github/workflows/${workflow}.yml"
  done
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
