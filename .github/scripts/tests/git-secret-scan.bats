#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/git-secret-scan.yml"
  for id in plan range trufflehog; do
    yq -r ".jobs.trufflehog.steps[] | select(.id == \"${id}\") | .run" "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/${id}.sh"
  done
  yq -r '.jobs.trufflehog.steps[] | select(.name == "Report and enforce results") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/report.sh"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output"
  export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary"
  export RUNNER_TEMP="${BATS_TEST_TMPDIR}/runner"
  mkdir -p "${RUNNER_TEMP}" "${BATS_TEST_TMPDIR}/bin"
  : > "${GITHUB_OUTPUT}"
  : > "${GITHUB_STEP_SUMMARY}"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  cat > "${BATS_TEST_TMPDIR}/bin/docker" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${DOCKER_ARGS}"
printf '%s' "${DOCKER_STDOUT:-}"
printf '%s\n' "${DOCKER_STDERR:-}" >&2
exit "${DOCKER_EXIT_CODE:-0}"
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/docker"
  export DOCKER_ARGS="${BATS_TEST_TMPDIR}/docker-args"
}

make_repo() {
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${REPO}"
  git -C "${REPO}" init -q -b main
  git -C "${REPO}" config user.email ci@example.invalid
  git -C "${REPO}" config user.name test
  git -C "${REPO}" commit -q --allow-empty -m one
  BASE="$(git -C "${REPO}" rev-parse HEAD)"
  git -C "${REPO}" commit -q --allow-empty -m two
  HEAD_SHA="$(git -C "${REPO}" rev-parse HEAD)"
}

step_output() {
  grep "^$1=" "${GITHUB_OUTPUT}" | tail -n 1 | cut -d= -f2-
}

@test "Git secret scan is read-only, pinned, and never uploads results" {
  [ "$(yq -r '.permissions | keys | join(",")' "${WORKFLOW}")" = contents ]
  [ "$(yq -r '.permissions.contents' "${WORKFLOW}")" = read ]
  [ "$(yq -r '.on.workflow_call.inputs."scan-mode".default' "${WORKFLOW}")" = range ]
  [ "$(yq -r '.on.workflow_call.inputs.verify.default' "${WORKFLOW}")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."fail-on-findings".default' "${WORKFLOW}")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."fail-on-unverified".default' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.secrets // "none"' "${WORKFLOW}")" = none ]
  grep -Eq 'trufflesecurity/trufflehog:[0-9.]+@sha256:[0-9a-f]{64}' "${WORKFLOW}"
  grep -Fq 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' "${WORKFLOW}"
  [ "$(yq -r '.jobs.trufflehog.steps[] | select(.name == "Checkout repository") | .with."persist-credentials"' "${WORKFLOW}")" = false ]
  ! grep -Fq 'upload-artifact' "${WORKFLOW}"
  ! grep -Fq -- '--fail' "${WORKFLOW}"
  ! grep -Eq '^\s*uses: .*@(v[0-9]|main|master)' "${WORKFLOW}"
}

@test "Source security scan stays limited to OSV-Scanner, Trivy, and Semgrep" {
  local src="${REPO_ROOT}/.github/workflows/source-security-scan.yml"
  ! grep -Eqi 'trufflehog|scorecard|zaproxy|zap-|cosign' "${src}"
  [ "$(yq -r '.permissions | keys | join(",")' "${src}")" = contents ]
}

@test "Plan rejects pull_request_target and sizes PR checkout depth" {
  run env EVENT_NAME=pull_request_target SCAN_MODE=range PR_COMMITS=3 bash "${BATS_TEST_TMPDIR}/plan.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"pull_request_target is not supported"* ]]
  run env EVENT_NAME=pull_request SCAN_MODE=range PR_COMMITS=3 bash "${BATS_TEST_TMPDIR}/plan.sh"
  [ "${status}" -eq 0 ]
  [ "$(step_output fetch-depth)" = 4 ]
  run env EVENT_NAME=pull_request SCAN_MODE=full PR_COMMITS=3 bash "${BATS_TEST_TMPDIR}/plan.sh"
  [ "$(step_output fetch-depth)" = 0 ]
  run env EVENT_NAME=schedule SCAN_MODE=range PR_COMMITS= bash "${BATS_TEST_TMPDIR}/plan.sh"
  [ "$(step_output fetch-depth)" = 0 ]
}

@test "Range resolution handles commit ranges, empty ranges, and bad input" {
  make_repo
  cd "${REPO}"
  run env SCAN_MODE=range BASE_INPUT="${BASE}" PR_BASE= PUSH_BEFORE= bash "${BATS_TEST_TMPDIR}/range.sh"
  [ "${status}" -eq 0 ]
  [ "$(step_output base)" = "${BASE}" ]
  [ "$(step_output head)" = "${HEAD_SHA}" ]
  [ "$(step_output skip)" = false ]

  : > "${GITHUB_OUTPUT}"
  run env SCAN_MODE=range BASE_INPUT= PR_BASE="${HEAD_SHA}" PUSH_BEFORE= bash "${BATS_TEST_TMPDIR}/range.sh"
  [ "${status}" -eq 0 ]
  [ "$(step_output skip)" = true ]

  : > "${GITHUB_OUTPUT}"
  run env SCAN_MODE=full BASE_INPUT= PR_BASE= PUSH_BEFORE= bash "${BATS_TEST_TMPDIR}/range.sh"
  [ "${status}" -eq 0 ]
  [ -z "$(step_output base)" ]
  [ "$(step_output skip)" = false ]

  run env SCAN_MODE=range BASE_INPUT= PR_BASE= PUSH_BEFORE=0000000000000000000000000000000000000000 bash "${BATS_TEST_TMPDIR}/range.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"need a base"* ]]
  run env SCAN_MODE=range BASE_INPUT=1111111111111111111111111111111111111111 PR_BASE= PUSH_BEFORE= bash "${BATS_TEST_TMPDIR}/range.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"not in the checked-out history"* ]]
  run env SCAN_MODE=weird BASE_INPUT= PR_BASE= PUSH_BEFORE= bash "${BATS_TEST_TMPDIR}/range.sh"
  [ "${status}" -eq 1 ]
}

@test "TruffleHog runs offline when verification is off and bounds the range" {
  run env GITHUB_WORKSPACE="${BATS_TEST_TMPDIR}" TRUFFLEHOG_IMAGE=img@sha256:x SCAN_MODE=range BASE_SHA=aaa HEAD_SHA=bbb VERIFY=false bash "${BATS_TEST_TMPDIR}/trufflehog.sh"
  [ "${status}" -eq 0 ]
  mapfile -t args < "${DOCKER_ARGS}"
  [[ " ${args[*]} " == *" --network none "* ]]
  [[ " ${args[*]} " == *" --no-verification "* ]]
  [[ " ${args[*]} " == *" --since-commit aaa --branch bbb "* ]]
  [[ " ${args[*]} " != *" --fail "* ]]
  [[ " ${args[*]} " == *"type=bind,source=${BATS_TEST_TMPDIR},target=/repo,readonly"* ]]

  run env GITHUB_WORKSPACE="${BATS_TEST_TMPDIR}" TRUFFLEHOG_IMAGE=img@sha256:x SCAN_MODE=full BASE_SHA= HEAD_SHA=bbb VERIFY=true bash "${BATS_TEST_TMPDIR}/trufflehog.sh"
  [ "${status}" -eq 0 ]
  mapfile -t args < "${DOCKER_ARGS}"
  [[ " ${args[*]} " != *" --network none "* ]]
  [[ " ${args[*]} " != *" --since-commit "* ]]
}

@test "Scanner failure fails the job without a results output" {
  run env GITHUB_WORKSPACE="${BATS_TEST_TMPDIR}" TRUFFLEHOG_IMAGE=img SCAN_MODE=full BASE_SHA= HEAD_SHA=bbb VERIFY=true DOCKER_EXIT_CODE=2 DOCKER_STDERR='boom' bash "${BATS_TEST_TMPDIR}/trufflehog.sh"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"TruffleHog failed with exit code 2"* ]]
  ! grep -q '^results=' "${GITHUB_OUTPUT}"
}

write_verified_and_unverified() {
  cat > "${BATS_TEST_TMPDIR}/results.jsonl" << 'JSON'
{"DetectorName":"AWS","Verified":true,"Raw":"AKIASECRETVALUE0000","RawV2":"supersecretvalue","Redacted":"AKIA...","SourceMetadata":{"Data":{"Git":{"file":"config/prod.env","line":3,"commit":"0123456789abcdef"}}}}
{"DetectorName":"Slack","Verified":false,"Raw":"xoxb-UNVERIFIEDVALUE","SourceMetadata":{"Data":{"Git":{"file":"notes.md","line":9,"commit":"fedcba9876543210"}}}}
JSON
}

write_unverified_only() {
  cat > "${BATS_TEST_TMPDIR}/results.jsonl" << 'JSON'
{"DetectorName":"Slack","Verified":false,"Raw":"xoxb-UNVERIFIEDVALUE","SourceMetadata":{"Data":{"Git":{"file":"notes.md","line":9,"commit":"fedcba9876543210"}}}}
JSON
}

run_report() {
  run env RESULTS_FILE="${BATS_TEST_TMPDIR}/results.jsonl" FAIL_ON_FINDINGS="$1" FAIL_ON_UNVERIFIED="$2" bash "${BATS_TEST_TMPDIR}/report.sh"
}

@test "Verified findings fail and secret values never reach logs or summary" {
  write_verified_and_unverified
  run_report true false
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"1 verified secret(s)"* ]]
  [[ "${output}" != *SECRETVALUE* && "${output}" != *supersecret* && "${output}" != *UNVERIFIEDVALUE* ]]
  ! grep -Eq 'SECRETVALUE|supersecret|UNVERIFIEDVALUE|AKIA' "${GITHUB_STEP_SUMMARY}"
  grep -Fq 'config/prod.env:3' "${GITHUB_STEP_SUMMARY}"
  grep -Fq '01234567' "${GITHUB_STEP_SUMMARY}"
}

@test "Unverified findings warn unless fail-on-unverified is set" {
  write_unverified_only
  run_report true false
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"::warning::1 unverified"* ]]
  [[ "${output}" != *UNVERIFIEDVALUE* ]]
  run_report true true
  [ "${status}" -eq 1 ]
  [[ "${output}" != *UNVERIFIEDVALUE* ]]
}

@test "Verified findings only warn when fail-on-findings is false, and empty results pass" {
  write_verified_and_unverified
  run_report false false
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"::warning::1 verified"* ]]
  : > "${BATS_TEST_TMPDIR}/results.jsonl"
  run_report true true
  [ "${status}" -eq 0 ]
}
