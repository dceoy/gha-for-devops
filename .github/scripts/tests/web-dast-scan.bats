#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/web-dast-scan.yml"
  yq -r '.jobs.zap.steps[] | select(.name == "Validate scan request") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/validate.sh"
  yq -r '.jobs.zap.steps[] | select(.id == "zap") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/zap.sh"
  yq -r '.jobs.zap.steps[] | select(.id == "redact") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/redact.sh"
  yq -r '.jobs.zap.steps[] | select(.name == "Enforce fail policy") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/enforce.sh"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output"
  export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary"
  export RUNNER_TEMP="${BATS_TEST_TMPDIR}/runner"
  mkdir -p "${RUNNER_TEMP}" "${BATS_TEST_TMPDIR}/bin"
  : > "${GITHUB_OUTPUT}"
  : > "${GITHUB_STEP_SUMMARY}"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  export DOCKER_ARGS="${BATS_TEST_TMPDIR}/docker-args"
  cat > "${BATS_TEST_TMPDIR}/bin/docker" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${DOCKER_ARGS}"
if [[ "${DOCKER_WRITE_REPORT:-true}" == true ]]; then
  printf '{"site":[]}' > "${RUNNER_TEMP}/zap-wrk/report.json"
fi
exit "${DOCKER_EXIT_CODE:-0}"
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/docker"
}

validate() {
  # usage: validate KEY=VALUE...; defaults describe a valid passive baseline request
  run env EVENT_NAME=workflow_call IS_FORK= TARGET_URL=https://staging.example.test/app CONFIRMED=true \
    SCAN_MODE=baseline API_DEFINITION= API_FORMAT=openapi ACTIVE_SCAN=false ENVIRONMENT= FAIL_ON_RISK=high \
    "$@" bash "${BATS_TEST_TMPDIR}/validate.sh"
}

@test "Web DAST workflow is read-only, pinned, passive by default, and creates no issues" {
  [ "$(yq -r '.permissions | keys | join(",")' "${WORKFLOW}")" = contents ]
  [ "$(yq -r '.on.workflow_call.inputs."scan-mode".default' "${WORKFLOW}")" = baseline ]
  [ "$(yq -r '.on.workflow_call.inputs."active-scan".default' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."confirm-authorized".default' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."fail-on-risk".default' "${WORKFLOW}")" = high ]
  [ "$(yq -r '.jobs.zap.runs-on' "${WORKFLOW}")" = ubuntu-latest ]
  grep -Eq 'ghcr.io/zaproxy/zaproxy:stable@sha256:[0-9a-f]{64}' "${WORKFLOW}"
  grep -Fq 'actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9' "${WORKFLOW}"
  ! grep -Eq '^\s*uses: .*@(v[0-9]|main|master)' "${WORKFLOW}"
  ! grep -Eq 'issues: write|allow_issue_writing: true|gh issue' "${WORKFLOW}"
  [ "$(yq -r '.on.workflow_call.secrets // "none"' "${WORKFLOW}")" = none ]
}

@test "Validation accepts authorized passive and API requests" {
  validate
  [ "${status}" -eq 0 ]
  validate SCAN_MODE=api API_DEFINITION=openapi.yaml
  [ "${status}" -eq 0 ]
  validate SCAN_MODE=api API_DEFINITION=https://staging.example.test/openapi.json API_FORMAT=graphql
  [ "${status}" -eq 0 ]
  validate SCAN_MODE=api API_DEFINITION=openapi.yaml ACTIVE_SCAN=true ENVIRONMENT=staging
  [ "${status}" -eq 0 ]
}

@test "Validation refuses unauthorized, unsafe, or production-active requests" {
  validate CONFIRMED=false
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"confirm-authorized"* ]]
  validate EVENT_NAME=pull_request_target
  [ "${status}" -eq 1 ]
  validate IS_FORK=true
  [ "${status}" -eq 1 ]
  validate TARGET_URL='ftp://staging.example.test'
  [ "${status}" -eq 1 ]
  validate TARGET_URL='https://user:pass@staging.example.test'
  [ "${status}" -eq 1 ]
  validate TARGET_URL='http://169.254.169.254/latest'
  [ "${status}" -eq 1 ]
  validate SCAN_MODE=full
  [ "${status}" -eq 1 ]
  validate SCAN_MODE=api API_DEFINITION=
  [ "${status}" -eq 1 ]
  validate SCAN_MODE=api API_DEFINITION=../secrets.yaml
  [ "${status}" -eq 1 ]
  validate SCAN_MODE=api API_DEFINITION=http://insecure.example/openapi.json
  [ "${status}" -eq 1 ]
  validate SCAN_MODE=api API_DEFINITION=openapi.yaml API_FORMAT=wsdl
  [ "${status}" -eq 1 ]
  validate FAIL_ON_RISK=critical
  [ "${status}" -eq 1 ]
  validate ACTIVE_SCAN=true
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"only supported in api mode"* ]]
  validate SCAN_MODE=api API_DEFINITION=openapi.yaml ACTIVE_SCAN=true ENVIRONMENT=Production
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"production-looking"* ]]
}

run_zap() {
  run env TARGET_URL=https://staging.example.test SCAN_MODE=baseline API_DEFINITION= API_FORMAT=openapi \
    ACTIVE_SCAN=false SPIDER_MINUTES=2 SCAN_TIMEOUT=7 ZAP_IMAGE=zap@sha256:x "$@" bash "${BATS_TEST_TMPDIR}/zap.sh"
}

@test "Baseline runs the passive script with host networking and no alert-based exit" {
  run_zap
  [ "${status}" -eq 0 ]
  mapfile -t args < "${DOCKER_ARGS}"
  [[ " ${args[*]} " == *" --network host "* ]]
  [[ " ${args[*]} " == *" zap-baseline.py -t https://staging.example.test -m 2 -T 7 "* ]]
  [[ " ${args[*]} " == *" -J report.json -r report.html -I "* ]]
  [[ " ${args[*]} " != *" -a "* ]]
}

@test "API scans stay in safe mode unless active scanning is opted in" {
  cd "${BATS_TEST_TMPDIR}"
  printf 'openapi: 3.0.0\n' > openapi.yaml
  run_zap SCAN_MODE=api API_DEFINITION=openapi.yaml
  [ "${status}" -eq 0 ]
  mapfile -t args < "${DOCKER_ARGS}"
  [[ " ${args[*]} " == *" zap-api-scan.py -t /zap/wrk/api-definition -f openapi -O https://staging.example.test -T 7 -S "* ]]
  [ -f "${RUNNER_TEMP}/zap-wrk/api-definition" ]

  run_zap SCAN_MODE=api API_DEFINITION=openapi.yaml ACTIVE_SCAN=true
  [ "${status}" -eq 0 ]
  mapfile -t args < "${DOCKER_ARGS}"
  [[ " ${args[*]} " != *" -S "* ]]
}

@test "Remote API definitions are passed as the target and missing files fail" {
  run_zap SCAN_MODE=api API_DEFINITION=https://staging.example.test/graphql API_FORMAT=graphql
  [ "${status}" -eq 0 ]
  mapfile -t args < "${DOCKER_ARGS}"
  [[ " ${args[*]} " == *" zap-api-scan.py -t https://staging.example.test/graphql -f graphql "* ]]
  cd "${BATS_TEST_TMPDIR}"
  run_zap SCAN_MODE=api API_DEFINITION=missing.yaml
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"api-definition not found"* ]]
}

@test "ZAP scan errors and missing reports fail the job" {
  run_zap DOCKER_EXIT_CODE=3
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"ZAP scan failed (exit code 3)"* ]]
  run_zap DOCKER_WRITE_REPORT=false
  [ "${status}" -eq 1 ]
  # Alert-bearing exit codes 1 and 2 are handled by the fail-on-risk policy instead.
  run_zap DOCKER_EXIT_CODE=2
  [ "${status}" -eq 0 ]
}

@test "Reports are redacted before upload and raw output is removed" {
  local workdir="${RUNNER_TEMP}/zap-wrk"
  mkdir -p "${workdir}"
  cat > "${workdir}/report.json" << 'JSON'
{"site":[{"alerts":[{"name":"Leak","riskcode":"2","evidence":"Authorization: Bearer abc.def-ghi\r\nCookie: sid=SESSIONSECRET; other=1\r\nGET /x?api_key=KEY123&ok=1 token=TOKEN456 eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.sig"}]}]}
JSON
  printf '<p>Set-Cookie: session=HTMLSECRET; Path=/</p>' > "${workdir}/report.html"
  run env WORKDIR="${workdir}" bash "${BATS_TEST_TMPDIR}/redact.sh"
  [ "${status}" -eq 0 ]
  [ ! -e "${workdir}" ]
  local out="${RUNNER_TEMP}/zap-report"
  ! grep -Eq 'abc\.def|SESSIONSECRET|KEY123|TOKEN456|eyJhbGci|HTMLSECRET' "${out}/report.json" "${out}/report.html"
  grep -Fq '[REDACTED]' "${out}/report.json"
  grep -Fq 'ok=1' "${out}/report.json"
  jq -e '.site[0].alerts[0].name == "Leak"' "${out}/report.json"
}

write_report() {
  cat > "${BATS_TEST_TMPDIR}/report.json" << 'JSON'
{"site":[{"alerts":[
  {"name":"Info thing","riskcode":"0","riskdesc":"Informational (Medium)","count":"1"},
  {"name":"Low thing","riskcode":"1","riskdesc":"Low (Medium)","count":"2"},
  {"name":"Medium thing","riskcode":"2","riskdesc":"Medium (High)","count":"3"}
]}]}
JSON
}

run_enforce() {
  run env REPORT="${BATS_TEST_TMPDIR}/report.json" FAIL_ON_RISK="$1" bash "${BATS_TEST_TMPDIR}/enforce.sh"
}

@test "Severity policy fails only at or above the chosen risk" {
  write_report
  run_enforce high
  [ "${status}" -eq 0 ]
  run_enforce medium
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"1 ZAP alert type(s) at or above 'medium'"* ]]
  run_enforce low
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"2 ZAP alert"* ]]
  run_enforce none
  [ "${status}" -eq 0 ]
  grep -Fq 'Medium thing' "${GITHUB_STEP_SUMMARY}"
}

@test "An empty report passes every policy" {
  printf '{"site":[]}' > "${BATS_TEST_TMPDIR}/report.json"
  run_enforce low
  [ "${status}" -eq 0 ]
}
