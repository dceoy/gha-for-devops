#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  REUSABLE="${REPO_ROOT}/.github/workflows/scorecard-assessment.yml"
  DEDICATED="${REPO_ROOT}/.github/workflows/maintenance.yml"
  yq -r '.jobs.scorecard.steps[] | select(.name == "Validate inputs") | .run' "${REUSABLE}" > "${BATS_TEST_TMPDIR}/validate.sh"
  yq -r '.jobs.scorecard.steps[] | select(.id == "summary") | .run' "${REUSABLE}" > "${BATS_TEST_TMPDIR}/summary.sh"
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

@test "Reusable Scorecard is internal-only with explicit read permissions" {
  [ "$(yq -r '.permissions.contents' "${REUSABLE}")" = read ]
  [ "$(yq -r '.permissions.actions' "${REUSABLE}")" = read ]
  [ "$(yq -r '.on.workflow_call.inputs | has("publish-results")' "${REUSABLE}")" = false ]
  [ "$(yq -r '.jobs | has("analysis")' "${REUSABLE}")" = false ]
  [ "$(yq -r '.jobs.scorecard.steps[] | select(.uses == "ossf/scorecard-action*") | .with.publish_results' "${REUSABLE}")" = false ]
  yq -r '.jobs.scorecard.steps[] | select(.uses == "ossf/scorecard-action*") | .uses' "${REUSABLE}" \
    | grep -Eq '^ossf/scorecard-action@[a-f0-9]{40}$'
  [ "$(yq -r '.on.workflow_call.inputs."min-score".default' "${REUSABLE}")" = "" ]
  [ "$(yq -r '.on.workflow_call.secrets.SCORECARD_TOKEN.required' "${REUSABLE}")" = false ]
}

@test "Result upload is not gated on hashFiles outside the workspace" {
  run ! grep -Fq 'hashFiles' "${REUSABLE}"
  [ "$(yq -r '.jobs.scorecard.steps[] | select(.name == "Upload Scorecard result") | .if' "${REUSABLE}")" != "" ]
}

@test "Empty artifact name disables upload while summary uses the local result" {
  [ "$(yq -r '.jobs.scorecard.steps[] | select(.name == "Upload Scorecard result") | .if' "${REUSABLE}")" = "\${{ !cancelled() && inputs.results-artifact-name != '' }}" ]
  [ "$(yq -r '.jobs.scorecard.steps[] | select(.id == "summary") | .env.RESULT_FILE' "${REUSABLE}")" = "\${{ runner.temp }}/scorecard.json" ]
  run ! grep -Fq 'scorecard-summary-transfer' "${REUSABLE}"
}

@test "Maintenance runs independent public Scorecard job under publishing restrictions" {
  [ "$(yq -r '.permissions.contents' "${DEDICATED}")" = read ]
  [ "$(yq -r '. | has("env") or has("defaults")' "${DEDICATED}")" = false ]
  [ "$(yq -r '.on | has("workflow_call")' "${DEDICATED}")" = false ]
  [ "$(yq -r '.on | has("schedule")' "${DEDICATED}")" = true ]
  [ "$(yq -r '.on | has("workflow_dispatch")' "${DEDICATED}")" = true ]
  [ "$(yq -r '.jobs.analysis | has("uses") or has("env") or has("defaults")' "${DEDICATED}")" = false ]
  [ "$(yq -r '.jobs.analysis.runs-on' "${DEDICATED}")" = ubuntu-latest ]
  [ "$(yq -r '.jobs.analysis.permissions."id-token"' "${DEDICATED}")" = write ]
  [ "$(yq -r '.jobs.analysis.permissions."security-events"' "${DEDICATED}")" = write ]
  [ "$(yq -r '.jobs.analysis.steps[] | select(.uses == "ossf/scorecard-action*") | .with.publish_results' "${DEDICATED}")" = true ]
  [ "$(yq -r '[.jobs.analysis.steps[] | select(has("run"))] | length' "${DEDICATED}")" = 0 ]
  [ "$(yq -r '.jobs.analysis.steps | length' "${DEDICATED}")" = 4 ]
  run bash -c 'yq -r '\''.jobs.analysis.steps[].uses'\'' "$1" | grep -Ev '\''^(actions/checkout|actions/upload-artifact|ossf/scorecard-action|github/codeql-action/upload-sarif)@'\''' _ "${DEDICATED}"
  [ "${status}" -eq 1 ]
  run ! grep -Eq '^[[:space:]]*uses: .*@(v[0-9]|main|master)' "${DEDICATED}"
}

@test "Checkov runs without a Scorecard permission-policy exemption" {
  local ci="${REPO_ROOT}/.github/workflows/ci.yml"
  local scanner="${REPO_ROOT}/.github/workflows/source-security-scan.yml"
  local qa="${REPO_ROOT}/.agents/skills/local-qa/scripts/qa.sh"
  for caller in "${ci}" "${DEDICATED}"; do
    [ "$(yq -r '.jobs."github-actions-lint-and-scan".with | has("checkov-exempt-file")' "${caller}")" = false ]
  done
  [ "$(yq -r '[.jobs.checkov.steps[] | select(.name == "Verify top-level permissions except approved reusable workflow")] | length' "${scanner}")" = 0 ]
  grep -Fq -- 'uv run --locked checkov --framework=all --output=github_failed_only --directory=.' "${qa}"
  run ! grep -Fq -- '--skip-check CKV2_GHA_1' "${qa}"
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
