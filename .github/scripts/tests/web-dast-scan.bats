#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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
printf '%s' "${DOCKER_STDOUT:-}"
exit "${DOCKER_EXIT_CODE:-0}"
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/docker"
}

validate() {
  # usage: validate KEY=VALUE...; defaults describe a valid passive baseline request
  run env EVENT_NAME=workflow_call IS_FORK= TARGET_URL=https://staging.example.test/app CONFIRMED=true \
    SCAN_MODE=baseline API_DEFINITION= API_FORMAT=openapi ACTIVE_SCAN=false ENVIRONMENT= FAIL_ON_RISK=high \
    "$@" bash -euo pipefail "${BATS_TEST_TMPDIR}/validate.sh"
}

@test "Web DAST workflow is read-only, pinned, passive by default, and creates no issues" {
  [ "$(yq -r '.permissions | keys | join(",")' "${WORKFLOW}")" = contents ]
  [ "$(yq -r '.on.workflow_call.inputs."scan-mode".default' "${WORKFLOW}")" = baseline ]
  [ "$(yq -r '.on.workflow_call.inputs."active-scan".default' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."confirm-authorized".default' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."fail-on-risk".default' "${WORKFLOW}")" = high ]
  [ "$(yq -r '.jobs.zap.runs-on' "${WORKFLOW}")" = ubuntu-latest ]
  grep -Eq 'ghcr.io/zaproxy/zaproxy:stable@sha256:[0-9a-f]{64}' "${WORKFLOW}"
  yq -r '.jobs.zap.steps[] | select(.name == "Upload metadata-only ZAP report") | .uses' "${WORKFLOW}" \
    | grep -Eq '^actions/upload-artifact@[a-f0-9]{40}$'
  run ! grep -Eq '^\s*uses: .*@(v[0-9]|main|master)' "${WORKFLOW}"
  run ! grep -Eq 'issues: write|allow_issue_writing: true|gh issue' "${WORKFLOW}"
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
  validate SCAN_MODE=api API_DEFINITION=https://different.example.test/graphql API_FORMAT=graphql
  [ "${status}" -eq 1 ]
  validate SCAN_MODE=api API_DEFINITION=https://staging.example.test/service.wsdl API_FORMAT=soap ACTIVE_SCAN=true
  [ "${status}" -eq 1 ]
  validate SCAN_MODE=api API_DEFINITION=service.wsdl API_FORMAT=soap ACTIVE_SCAN=false
  [ "${status}" -eq 1 ]
  validate SCAN_MODE=api API_DEFINITION=openapi.yaml ACTIVE_SCAN=true ENVIRONMENT=Production
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"production-looking"* ]]
}

run_zap() {
  run env TARGET_URL=https://staging.example.test SCAN_MODE=baseline API_DEFINITION= API_FORMAT=openapi \
    ACTIVE_SCAN=false SPIDER_MINUTES=2 SCAN_TIMEOUT=7 ZAP_IMAGE=zap@sha256:x "$@" bash -euo pipefail "${BATS_TEST_TMPDIR}/zap.sh"
}

@test "Baseline runs the passive script with host networking and no alert-based exit" {
  run_zap
  [ "${status}" -eq 0 ]
  mapfile -t args < "${DOCKER_ARGS}"
  [[ " ${args[*]} " == *" --network host "* ]]
  [[ " ${args[*]} " == *" zap-baseline.py -t https://staging.example.test -m 2 -T 7 "* ]]
  [[ " ${args[*]} " == *" -J report.json -I "* ]]
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

@test "OpenAPI definitions preserve the authorized scheme, port, and path" {
  cd "${BATS_TEST_TMPDIR}"
  printf 'openapi: 3.0.0\n' > openapi.yaml
  local definition target
  for definition in openapi.yaml https://docs.example.test/openapi.json; do
    for target in http://localhost:3000/api https://staging.example.test:8443/api; do
      run_zap SCAN_MODE=api API_DEFINITION="${definition}" TARGET_URL="${target}" ACTIVE_SCAN=true
      [ "${status}" -eq 0 ]
      mapfile -t args < "${DOCKER_ARGS}"
      [[ " ${args[*]} " == *" -f openapi -O ${target} -T 7 "* ]]
      [[ " ${args[*]} " != *" -S "* ]]
    done
  done
}

@test "Local GraphQL schemas use the authorized endpoint and a schema file" {
  cd "${BATS_TEST_TMPDIR}"
  printf 'type Query { hello: String }\n' > schema.graphql
  run_zap SCAN_MODE=api API_DEFINITION=schema.graphql API_FORMAT=graphql TARGET_URL=http://localhost:3000/graphql
  [ "${status}" -eq 0 ]
  mapfile -t args < "${DOCKER_ARGS}"
  [[ " ${args[*]} " == *" zap-api-scan.py -t http://localhost:3000/graphql -f graphql --schema /zap/wrk/api-definition -T 7 -S "* ]]
  cmp schema.graphql "${RUNNER_TEMP}/zap-wrk/api-definition"
}

@test "Scanner output stays in a private log, not GitHub Actions output" {
  run_zap DOCKER_STDOUT='SENSITIVE-ZAP-EXAMPLE-URL'
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"SENSITIVE-ZAP-EXAMPLE-URL"* ]]
  grep -Fq 'SENSITIVE-ZAP-EXAMPLE-URL' "${RUNNER_TEMP}/zap-scan.log"
  [ "$(stat -c %a "${RUNNER_TEMP}/zap-scan.log")" = 600 ]
  run_zap DOCKER_EXIT_CODE=3 DOCKER_STDOUT='SENSITIVE-ZAP-EXAMPLE-URL'
  [ "${status}" -eq 1 ]
  [[ "${output}" != *"SENSITIVE-ZAP-EXAMPLE-URL"* ]]
}

@test "Remote GraphQL schema uses the authorized API endpoint" {
  run_zap SCAN_MODE=api API_DEFINITION=https://staging.example.test/schema.graphql API_FORMAT=graphql TARGET_URL=https://staging.example.test/graphql
  [ "${status}" -eq 0 ]
  mapfile -t args < "${DOCKER_ARGS}"
  [[ " ${args[*]} " == *" zap-api-scan.py -t https://staging.example.test/graphql -f graphql --schema https://staging.example.test/schema.graphql -T 7 -S "* ]]
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

@test "Only allowlisted numeric metadata survives the ZAP report" {
  local workdir="${RUNNER_TEMP}/zap-wrk"
  mkdir -p "${workdir}"
  local jwt_header="eyJhbGciOiJIUzI1NiJ9"
  local jwt_payload="eyJzdWIiOiIxMjM0NTY3ODkwIn0"
  cat > "${workdir}/report.json" << JSON
{"site":[{"alerts":[{"pluginid":"20002","name":"Leak","riskcode":"2","count":"3","url":"https://staging.example.test/callback?session_id=PRIVATEVALUE","evidence":"Authorization: Bearer abc.def-ghi\\r\\nCookie: sid=SESSIONSECRET\\r\\nGET /x?api_key=KEY123&ok=1 token=TOKEN456 ${jwt_header}.${jwt_payload}.sig"}]}]}
JSON
  printf '<p>Set-Cookie: session=HTMLSECRET; Path=/</p>' > "${workdir}/report.html"
  run env WORKDIR="${workdir}" bash -euo pipefail "${BATS_TEST_TMPDIR}/redact.sh"
  [ "${status}" -eq 0 ]
  [ ! -e "${workdir}" ]
  local out="${RUNNER_TEMP}/zap-report"
  [ -f "${out}/report.json" ]
  [ ! -f "${out}/report.html" ]
  jq -e '.alerts == [{"rule":"20002","risk":2,"instances":3}]' "${out}/report.json"
  run ! grep -Eq 'PRIVATEVALUE|SESSIONSECRET|KEY123|TOKEN456|eyJhbGci|HTMLSECRET|abc.def' "${out}/report.json"
}

@test "Unsafe or malformed ZAP metadata fails closed" {
  local workdir="${RUNNER_TEMP}/zap-wrk"
  mkdir -p "${workdir}"
  printf '{"site":[{"alerts":[{"riskcode":"PRIVATEVALUE"}]}]}' > "${workdir}/report.json"
  run env WORKDIR="${workdir}" bash -euo pipefail "${BATS_TEST_TMPDIR}/redact.sh"
  [ "${status}" -ne 0 ]
}

write_report() {
  cat > "${BATS_TEST_TMPDIR}/report.json" << 'JSON'
{"alerts":[
  {"rule":"10000","risk":0,"instances":1},
  {"rule":"10001","risk":1,"instances":2},
  {"rule":"20002","risk":2,"instances":3}
]}
JSON
}

run_enforce() {
  run env REPORT="${BATS_TEST_TMPDIR}/report.json" FAIL_ON_RISK="$1" bash -euo pipefail "${BATS_TEST_TMPDIR}/enforce.sh"
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
  grep -Fq '20002' "${GITHUB_STEP_SUMMARY}"
}

@test "An empty report passes every policy" {
  printf '{"alerts":[]}' > "${BATS_TEST_TMPDIR}/report.json"
  run_enforce low
  [ "${status}" -eq 0 ]
}
