#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  REUSABLE="${REPO_ROOT}/.github/workflows/scorecard-assessment.yml"
  DEDICATED="${REPO_ROOT}/.github/workflows/maintenance.yml"
  yq -r '.jobs.summary.steps[] | select(.name == "Validate inputs") | .run' "${REUSABLE}" > "${BATS_TEST_TMPDIR}/validate.sh"
  yq -r '.jobs.summary.steps[] | select(.id == "summary") | .run' "${REUSABLE}" > "${BATS_TEST_TMPDIR}/summary.sh"
  export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary"
  : > "${GITHUB_STEP_SUMMARY}"
  cat > "${BATS_TEST_TMPDIR}/scorecard.json" << 'JSON'
{"score":6.4,"checks":[
  {"name":"Pinned-Dependencies","score":10,"reason":"all pinned","documentation":{"url":"https://example.invalid/pinned"}},
  {"name":"Code-Review","score":3,"reason":"found 2 unreviewed | changesets\nsecond line","documentation":{"url":"https://example.invalid/review"}},
  {"name":"Branch-Protection","score":-1,"reason":"internal error: token lacks access","documentation":{"url":"https://example.invalid/bp"}}
]}
JSON
}

run_summary() {
  run env RESULT_FILE="${BATS_TEST_TMPDIR}/scorecard.json" MIN_SCORE="$1" bash -euo pipefail "${BATS_TEST_TMPDIR}/summary.sh"
}

@test "Reusable Scorecard publication is opt-in and uses a single scan job" {
  [ "$(yq -r '.on.workflow_call.inputs."publish-results".default' "${REUSABLE}")" = false ]
  [ "$(yq -r '.permissions.contents' "${REUSABLE}")" = read ]
  [ "$(yq -r '.permissions.actions' "${REUSABLE}")" = read ]
  [ "$(yq -r '. | has("env") or has("defaults")' "${REUSABLE}")" = false ]
  [ "$(yq -r '.jobs.scorecard | has("env") or has("defaults")' "${REUSABLE}")" = false ]
  [[ "$(yq -r '.jobs.scorecard.steps[] | select(.name == "Run OpenSSF Scorecard") | .with.publish_results' "${REUSABLE}")" == *publish-results* ]]
  [[ "$(yq -r '.jobs.scorecard.steps[] | select(.name == "Run OpenSSF Scorecard") | .with.results_format' "${REUSABLE}")" == *publish-results* ]]
  [ "$(yq -r '[.jobs[].steps[] | select(.name == "Run OpenSSF Scorecard")] | length' "${REUSABLE}")" = 1 ]
  [ "$(yq -r '.jobs.scorecard.permissions."id-token"' "${REUSABLE}")" = write ]
  [ "$(yq -r '.jobs.scorecard.permissions."security-events"' "${REUSABLE}")" = write ]
  [ "$(yq -r '.on.workflow_call.inputs."min-score".default' "${REUSABLE}")" = "" ]
  [ "$(yq -r '.on.workflow_call.secrets.SCORECARD_TOKEN.required' "${REUSABLE}")" = false ]
  yq -r '.jobs.scorecard.steps[] | select(.name == "Run OpenSSF Scorecard") | .uses' "${REUSABLE}" \
    | grep -Eq '^ossf/scorecard-action@[a-f0-9]{40}$'
}

@test "Publishing job follows OpenSSF allowlist with no run steps" {
  [ "$(yq -r '.jobs.scorecard.steps[] | select(has("run")) | .name' "${REUSABLE}")" = "" ]
  yq -r '.jobs.scorecard.steps[] | .uses' "${REUSABLE}" \
    | grep -Ev '^(actions/checkout|actions/upload-artifact|ossf/scorecard-action|github/codeql-action/upload-sarif)@' |
    grep -q . && return 1
  [ "$(yq -r '.jobs.scorecard.steps[] | select(.name == "Upload Scorecard results to code scanning") | .if' "${REUSABLE}")" != "" ]
  [[ "$(yq -r '.jobs.summary.if' "${REUSABLE}")" == *publish-results* ]]
}

@test "Published maintenance Scorecard calls the reusable workflow" {
  [ "$(yq -r '.permissions.contents' "${DEDICATED}")" = read ]
  [ "$(yq -r '. | has("env") or has("defaults")' "${DEDICATED}")" = false ]
  [ "$(yq -r '.on | has("workflow_call")' "${DEDICATED}")" = false ]
  [ "$(yq -r '.on | has("schedule")' "${DEDICATED}")" = true ]
  [ "$(yq -r '.on | has("workflow_dispatch")' "${DEDICATED}")" = true ]
  [ "$(yq -r '.jobs.analysis.permissions."id-token"' "${DEDICATED}")" = write ]
  [ "$(yq -r '.jobs.analysis.permissions."security-events"' "${DEDICATED}")" = write ]
  [ "$(yq -r '.jobs.analysis.uses' "${DEDICATED}")" = '$/.github/workflows/scorecard-assessment.yml' ]
  [ "$(yq -r '.jobs.analysis.with."publish-results"' "${DEDICATED}")" = true ]
  run ! grep -Eq '^\s*uses: .*@(v[0-9]|main|master)' "${DEDICATED}"
}

@test "Score alone does not fail the job and failing checks are listed" {
  run_summary ""
  [ "${status}" -eq 0 ]
  grep -Fq 'Aggregate score: 6.4' "${GITHUB_STEP_SUMMARY}"
  grep -Fq 'not a vulnerability count' "${GITHUB_STEP_SUMMARY}"
  grep -Fq '[Code-Review]' "${GITHUB_STEP_SUMMARY}"
  grep -Fq 'inconclusive' "${GITHUB_STEP_SUMMARY}"
  run ! grep -Fq 'Pinned-Dependencies' "${GITHUB_STEP_SUMMARY}"
}

@test "min-score gates the job only when set" {
  run_summary 7
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"below min-score 7"* ]]
  run_summary 6.4
  [ "${status}" -eq 0 ]
}

@test "min-score input is validated" {
  run env MIN_SCORE=abc bash -euo pipefail "${BATS_TEST_TMPDIR}/validate.sh"
  [ "${status}" -eq 1 ]
  run env MIN_SCORE=11 bash -euo pipefail "${BATS_TEST_TMPDIR}/validate.sh"
  [ "${status}" -eq 1 ]
  run env MIN_SCORE=10.1 bash -euo pipefail "${BATS_TEST_TMPDIR}/validate.sh"
  [ "${status}" -eq 1 ]
  run env MIN_SCORE=10.999 bash -euo pipefail "${BATS_TEST_TMPDIR}/validate.sh"
  [ "${status}" -eq 1 ]
  run env MIN_SCORE=10.0 bash -euo pipefail "${BATS_TEST_TMPDIR}/validate.sh"
  [ "${status}" -eq 0 ]
  run env MIN_SCORE=7.5 bash -euo pipefail "${BATS_TEST_TMPDIR}/validate.sh"
  [ "${status}" -eq 0 ]
  run env MIN_SCORE= bash -euo pipefail "${BATS_TEST_TMPDIR}/validate.sh"
  [ "${status}" -eq 0 ]
}
