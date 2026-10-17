#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/strix-scan.yml"
  yq -r '.jobs.strix.steps[] | select(.name == "Validate scan request") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/validate.sh"
  yq -r '.jobs.strix.steps[] | select(.id == "scan") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/scan.sh"
  export GITHUB_WORKSPACE="${BATS_TEST_TMPDIR}/repo"
  export RUNNER_TEMP="${BATS_TEST_TMPDIR}/runner"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/outputs"
  export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary"
  export UVX_ARGS="${BATS_TEST_TMPDIR}/uvx-args"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  mkdir -p "${GITHUB_WORKSPACE}" "${RUNNER_TEMP}" "${BATS_TEST_TMPDIR}/bin"
  : > "${GITHUB_OUTPUT}"
  : > "${GITHUB_STEP_SUMMARY}"
  git -C "${GITHUB_WORKSPACE}" init -q -b main
  git -C "${GITHUB_WORKSPACE}" config user.name test
  git -C "${GITHUB_WORKSPACE}" config user.email test@example.invalid
  git -C "${GITHUB_WORKSPACE}" commit -q --allow-empty -m first
  export PR_BASE_SHA="$(git -C "${GITHUB_WORKSPACE}" rev-parse HEAD)"
  git -C "${GITHUB_WORKSPACE}" commit -q --allow-empty -m second
  cat > "${BATS_TEST_TMPDIR}/bin/uvx" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${UVX_ARGS}"
mkdir -p strix_runs/test
printf '{"status":"%s","llm_usage":{"cost":%s}}' "${FAKE_RUN_STATUS:-completed}" "${FAKE_COST:-1}" > strix_runs/test/run.json
printf '{"version":"2.1.0","runs":[]}' > strix_runs/test/findings.sarif
echo 'SENSITIVE-SCAN-FINDING-WITH-SECRET'
exit "${FAKE_EXIT_CODE:-0}"
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/uvx"
}

validate() {
  run env EVENT_NAME=workflow_dispatch IS_FORK= CONFIRMED=true TARGET_PATH=. \
    SCAN_MODE=quick SCOPE_MODE=auto MAX_BUDGET=10 FAIL_ON=high ENVIRONMENT=staging \
    "$@" bash "${BATS_TEST_TMPDIR}/validate.sh"
}

scan() {
  run env STRIX_LLM=openrouter/example/model LLM_API_KEY=example-secret TARGET_PATH=. \
    SCAN_MODE=quick SCOPE_MODE=auto MAX_BUDGET=10 FAIL_ON=high EVENT_NAME=workflow_dispatch \
    PR_BASE_SHA= UPLOAD_SARIF=false STRIX_VERSION=1.7.0 \
    "$@" bash "${BATS_TEST_TMPDIR}/scan.sh"
}

@test "Strix workflow is an opt-in, version-pinned reusable workflow" {
  [ "$(yq -r '.on.workflow_call.inputs."confirm-authorized".default' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."scan-mode".default' "${WORKFLOW}")" = quick ]
  [ "$(yq -r '.on.workflow_call.inputs."fail-on".default' "${WORKFLOW}")" = high ]
  [ "$(yq -r '.on.workflow_call.inputs."upload-sarif".default' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.jobs.strix.runs-on' "${WORKFLOW}")" = ubuntu-latest ]
  [ "$(yq -r '.jobs.strix.env.STRIX_VERSION' "${WORKFLOW}")" = 1.7.0 ]
  [ "$(yq -r '.permissions.contents' "${WORKFLOW}")" = read ]
  [ "$(yq -r '.jobs.strix.permissions."security-events"' "${WORKFLOW}")" = write ]
  [ "$(yq -r '.on.workflow_call.secrets.STRIX_LLM.required' "${WORKFLOW}")" = true ]
  [ "$(yq -r '.on.workflow_call.secrets.LLM_API_KEY.required' "${WORKFLOW}")" = true ]
  grep -Fq 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' "${WORKFLOW}"
  grep -Fq 'astral-sh/setup-uv@1c37ad07a6a961277cf70c0d37d6f313000f5884' "${WORKFLOW}"
  run ! grep -Eq '^\s*uses: .*@(v[0-9]|main|master)' "${WORKFLOW}"
  run ! grep -Eqi 'pull-requests: write|issues: write|upload-artifact' "${WORKFLOW}"
}

@test "Input validation rejects unauthorized or unsafe scan requests" {
  validate
  [ "${status}" -eq 0 ]
  validate CONFIRMED=false
  [ "${status}" -eq 1 ]
  validate EVENT_NAME=pull_request_target
  [ "${status}" -eq 1 ]
  validate IS_FORK=true
  [ "${status}" -eq 1 ]
  validate TARGET_PATH=/tmp
  [ "${status}" -eq 1 ]
  validate TARGET_PATH=https://example.test
  [ "${status}" -eq 1 ]
  validate TARGET_PATH=-delete
  [ "${status}" -eq 1 ]
  validate SCAN_MODE=anything
  [ "${status}" -eq 1 ]
  validate SCOPE_MODE=diff
  [ "${status}" -eq 1 ]
  validate FAIL_ON=none
  [ "${status}" -eq 1 ]
  validate MAX_BUDGET=0
  [ "${status}" -eq 1 ]
  validate MAX_BUDGET=NaN
  [ "${status}" -eq 1 ]
  validate ENVIRONMENT=Production
  [ "${status}" -eq 1 ]
}

@test "Strix runs quick scan with pinned uvx package and a full non-PR scope" {
  scan
  [ "${status}" -eq 0 ]
  mapfile -t args < "${UVX_ARGS}"
  [[ " ${args[*]} " == *" --from strix-agent==1.7.0 strix -n -t ${GITHUB_WORKSPACE} --scan-mode quick --max-budget 10 --fail-on high --scope-mode full "* ]]
  [[ " ${args[*]} " != *" --diff-base "* ]]
  grep -Fq 'exit_code=0' "${GITHUB_OUTPUT}"
  grep -Fq 'Scan status: completed' "${GITHUB_STEP_SUMMARY}"
  [[ "${output}" != *'SENSITIVE-SCAN-FINDING'* ]]
  [ -f "${RUNNER_TEMP}/strix-work/scan.log" ]
  [ "$(stat -c %a "${RUNNER_TEMP}/strix-work/scan.log")" = 600 ]
  run ! grep -Fq 'SENSITIVE-SCAN-FINDING' "${GITHUB_STEP_SUMMARY}"
  [ ! -f "${RUNNER_TEMP}/strix-findings.sarif" ]
}

@test "Pull requests are diff-scoped against the exact base commit" {
  scan EVENT_NAME=pull_request PR_BASE_SHA="${PR_BASE_SHA}"
  [ "${status}" -eq 0 ]
  mapfile -t args < "${UVX_ARGS}"
  [[ " ${args[*]} " == *" --scope-mode diff --diff-base ${PR_BASE_SHA} "* ]]
  scan EVENT_NAME=pull_request PR_BASE_SHA=bad
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'not available in checkout history'* ]]
}

@test "Exit code 2 carries validated findings without exposing scan logs" {
  scan FAKE_EXIT_CODE=2
  [ "${status}" -eq 0 ]
  grep -Fq 'exit_code=2' "${GITHUB_OUTPUT}"
  [[ "${output}" != *'SENSITIVE-SCAN-FINDING'* ]]
}

@test "Incomplete, error, and budget-near-limit runs fail closed" {
  scan FAKE_RUN_STATUS=stopped
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'not completed'* ]]
  scan FAKE_COST=9
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'90% of the budget'* ]]
  scan FAKE_EXIT_CODE=1
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'execution failed'* ]]
}

@test "SARIF is published only when explicitly enabled" {
  scan UPLOAD_SARIF=true
  [ "${status}" -eq 0 ]
  [ -f "${RUNNER_TEMP}/strix-findings.sarif" ]
  jq -e '.version == "2.1.0"' "${RUNNER_TEMP}/strix-findings.sarif"
  [ "$(yq -r '.jobs.strix.steps[] | select(.name == "Publish Strix findings to code scanning") | .if' "${WORKFLOW}")" = "!cancelled() && inputs.upload-sarif && steps.scan.outcome == 'success'" ]
}
