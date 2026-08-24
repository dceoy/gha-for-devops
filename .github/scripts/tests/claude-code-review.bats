#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/claude-code-review.yml"
  TEST_TEMP="$(mktemp -d)"
  FAKE_BIN="${TEST_TEMP}/bin"
  RUNNER_TEMP="${TEST_TEMP}/runner-temp"
  GH_CALLS_FILE="${TEST_TEMP}/gh-calls"
  GH_PAYLOAD_FILE="${TEST_TEMP}/payload.json"
  GH_POST_RESPONSE_FILE="${TEST_TEMP}/post-response.json"
  PR_HEAD_SHA="test-head-sha"
  GH_HEAD_SHA="${PR_HEAD_SHA}"
  REVIEW_MARKER='<!-- claude-code-review:test -->'
  mkdir -p "${FAKE_BIN}" "${RUNNER_TEMP}"

  export PATH="${FAKE_BIN}:${PATH}"
  export GITHUB_REPOSITORY=dceoy/gha-for-devops
  export PR_NUMBER=953
  export PR_HEAD_SHA GH_HEAD_SHA REVIEW_MARKER RUNNER_TEMP
  export GH_CALLS_FILE GH_PAYLOAD_FILE GH_POST_RESPONSE_FILE
  : > "${GH_CALLS_FILE}"
  printf '{"state":"COMMENTED","commit_id":"%s","body":"%s"}\n' \
    "${PR_HEAD_SHA}" "${REVIEW_MARKER}" > "${GH_POST_RESPONSE_FILE}"

  cat > "${FAKE_BIN}/gh" << 'GH_EOF'
#!/usr/bin/env bash
set -euo pipefail

method=GET
input_file=
next_argument=
for argument in "$@"; do
  case "${next_argument}" in
    method)
      method="${argument}"
      next_argument=
      ;;
    input)
      input_file="${argument}"
      next_argument=
      ;;
    *)
      case "${argument}" in
        --method)
          next_argument=method
          ;;
        --input)
          next_argument=input
          ;;
      esac
      ;;
  esac
done

printf '%s\n' "$*" >> "${GH_CALLS_FILE}"
if [[ "${method}" == GET ]]; then
  [[ "${GH_FAIL_STAGE:-}" != head ]] || exit 1
  printf '%s\n' "${GH_HEAD_SHA}"
  exit 0
fi

[[ "${method}" == POST && -n "${input_file}" ]] || exit 1
[[ "${GH_FAIL_STAGE:-}" != post ]] || exit 1
cp "${input_file}" "${GH_PAYLOAD_FILE}"
cat "${GH_POST_RESPONSE_FILE}"
GH_EOF
  chmod +x "${FAKE_BIN}/gh"
}

teardown() {
  rm -rf "${TEST_TEMP}"
}

extract_step() {
  local step_name="$1"
  local output_script="$2"

  yq -r ".jobs.\"claude-code-review\".steps[] | select(.name == \"${step_name}\") | .run" \
    "${WORKFLOW}" > "${output_script}"
}

write_execution_file() {
  local content="$1"

  CLAUDE_EXECUTION_FILE="${TEST_TEMP}/execution.json"
  export CLAUDE_EXECUTION_FILE
  printf '%s\n' "${content}" > "${CLAUDE_EXECUTION_FILE}"
}

reset_gh_state() {
  : > "${GH_CALLS_FILE}"
  rm -f "${GH_PAYLOAD_FILE}"
  GH_FAIL_STAGE=
  GH_HEAD_SHA="${PR_HEAD_SHA}"
  export GH_FAIL_STAGE GH_HEAD_SHA
}

run_publication() {
  local step_script="${TEST_TEMP}/ensure-comment-review.sh"

  extract_step "Ensure COMMENT review publication" "${step_script}"
  run env \
    GITHUB_REPOSITORY="${GITHUB_REPOSITORY}" \
    PR_NUMBER="${PR_NUMBER}" \
    PR_HEAD_SHA="${PR_HEAD_SHA}" \
    REVIEW_MARKER="${REVIEW_MARKER}" \
    RUNNER_TEMP="${RUNNER_TEMP}" \
    CLAUDE_EXECUTION_FILE="${CLAUDE_EXECUTION_FILE}" \
    bash -euo pipefail "${step_script}"
}

run_diagnosis() {
  local step_script="${TEST_TEMP}/diagnose-claude-review.sh"

  extract_step "Diagnose Claude Code failure" "${step_script}"
  run env \
    CLAUDE_EXECUTION_FILE="${CLAUDE_EXECUTION_FILE:-}" \
    CLAUDE_REVIEW_CONCLUSION="${CLAUDE_REVIEW_CONCLUSION}" \
    CLAUDE_REVIEW_OUTCOME="${CLAUDE_REVIEW_OUTCOME}" \
    bash -euo pipefail "${step_script}"
}

@test "publication selects the last non-empty successful result" {
  write_execution_file '[{"type":"result","subtype":"success","is_error":false,"result":"first"},{"type":"result","subtype":"success","is_error":false,"result":"last"}]'
  reset_gh_state

  run_publication

  [ "${status}" -eq 0 ]
  [ "$(jq -r '.event' "${GH_PAYLOAD_FILE}")" = COMMENT ]
  [ "$(jq -r '.commit_id' "${GH_PAYLOAD_FILE}")" = "${PR_HEAD_SHA}" ]
  [ "$(jq -r '.body' "${GH_PAYLOAD_FILE}")" = last$'\n\n'"${REVIEW_MARKER}" ]
}

@test "publication fails before POST without a non-empty successful result" {
  local -a case_names=(no-result empty-result unsuccessful-result)
  local -a case_inputs=(
    '[{"type":"result","subtype":"assistant","is_error":false,"result":"not a final result"}]'
    '[{"type":"result","subtype":"success","is_error":false,"result":""}]'
    '[{"type":"result","subtype":"success","is_error":true,"result":"failed"}]'
  )

  for i in "${!case_names[@]}"; do
    write_execution_file "${case_inputs[i]}"
    reset_gh_state

    run_publication

    [ "${status}" -ne 0 ] || {
      echo "case ${case_names[i]} unexpectedly passed" >&2
      return 1
    }
    [[ "${output}" == *"no non-empty successful review summary"* ]]
    [ ! -f "${GH_PAYLOAD_FILE}" ]
    ! grep -q -- '--method POST' "${GH_CALLS_FILE}"
  done
}

@test "publication skips a review when the PR head advances" {
  write_execution_file '[{"type":"result","subtype":"success","is_error":false,"result":"review"}]'
  GH_HEAD_SHA=advanced-head
  export GH_HEAD_SHA

  run_publication

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PR head advanced"* ]]
  [ ! -f "${GH_PAYLOAD_FILE}" ]
  run grep -q -- '--method POST' "${GH_CALLS_FILE}"
  [ "${status}" -ne 0 ]
}

@test "permission denials fail before the review POST" {
  write_execution_file '[{"type":"result","subtype":"success","is_error":false,"permission_denials":[{"tool_name":"Bash","command":"git push"}],"result":"incomplete"}]'

  run_publication

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Claude Code permission denials"* ]]
  [[ "${output}" == *"Bash"* ]]
  [ ! -f "${GH_PAYLOAD_FILE}" ]
  run grep -q -- '--method POST' "${GH_CALLS_FILE}"
  [ "${status}" -ne 0 ]
}

@test "publication fails before POST for missing or malformed execution files" {
  local -a case_names=(missing malformed)
  local -a case_inputs=(__missing__ not-json)

  for i in "${!case_names[@]}"; do
    reset_gh_state
    CLAUDE_EXECUTION_FILE="${TEST_TEMP}/${case_names[i]}.json"
    export CLAUDE_EXECUTION_FILE
    if [[ "${case_inputs[i]}" == __missing__ ]]; then
      rm -f "${CLAUDE_EXECUTION_FILE}"
    else
      printf '%s\n' "${case_inputs[i]}" > "${CLAUDE_EXECUTION_FILE}"
    fi

    run_publication

    [ "${status}" -ne 0 ] || {
      echo "case ${case_names[i]} unexpectedly passed" >&2
      return 1
    }
    ! grep -q -- '--method POST' "${GH_CALLS_FILE}"
  done
}

@test "head and review API failures stop publication" {
  local -a failure_stages=(head post)
  write_execution_file '[{"type":"result","subtype":"success","is_error":false,"result":"review"}]'

  for failure_stage in "${failure_stages[@]}"; do
    reset_gh_state
    GH_FAIL_STAGE="${failure_stage}"
    export GH_FAIL_STAGE

    run_publication

    [ "${status}" -ne 0 ] || {
      echo "case ${failure_stage} unexpectedly passed" >&2
      return 1
    }
  done
}

@test "diagnosis leaves a successful Claude review untouched" {
  CLAUDE_REVIEW_OUTCOME=success
  CLAUDE_REVIEW_CONCLUSION=success
  export CLAUDE_REVIEW_OUTCOME CLAUDE_REVIEW_CONCLUSION

  run_diagnosis

  [ "${status}" -eq 0 ]
}

@test "diagnosis fails for every non-success action state" {
  local -a outcomes=(success success failure cancelled)
  local -a conclusions=(empty failure success empty)
  write_execution_file '[{"type":"result","subtype":"error","is_error":true,"errors":["boom"]}]'

  for i in "${!outcomes[@]}"; do
    CLAUDE_REVIEW_OUTCOME="${outcomes[i]}"
    CLAUDE_REVIEW_CONCLUSION="${conclusions[i]}"
    if [[ "${CLAUDE_REVIEW_CONCLUSION}" == empty ]]; then
      CLAUDE_REVIEW_CONCLUSION=
    fi
    export CLAUDE_REVIEW_OUTCOME CLAUDE_REVIEW_CONCLUSION

    run_diagnosis

    [ "${status}" -ne 0 ] || {
      echo "case ${outcomes[i]}/${conclusions[i]} unexpectedly passed" >&2
      return 1
    }
  done
}

@test "diagnosis always runs and receives the Claude action status" {
  # shellcheck disable=SC2016
  local expected_outcome='${{ steps.claude-review.outcome }}'
  # shellcheck disable=SC2016
  local expected_conclusion='${{ steps.claude-review.outputs.conclusion }}'

  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Diagnose Claude Code failure") | .if' "${WORKFLOW}"
  [ "${output}" = "always()" ]

  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Diagnose Claude Code failure") | .env.CLAUDE_REVIEW_OUTCOME' "${WORKFLOW}"
  [ "${output}" = "${expected_outcome}" ]

  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Diagnose Claude Code failure") | .env.CLAUDE_REVIEW_CONCLUSION' "${WORKFLOW}"
  [ "${output}" = "${expected_conclusion}" ]
}

@test "Claude review is read-only by default and at runtime" {
  run yq -r '.on.workflow_call.inputs."claude-args".default' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'--allowedTools="Skill,Agent,Task,Read,Glob,Grep"'* ]]
  [[ "${output}" != *'Bash('* ]]
  [[ "${output}" != *'WebFetch'* ]]
  [[ "${output}" != *'WebSearch'* ]]
  [[ "${output}" != *'mcp__github_inline_comment__create_inline_comment'* ]]

  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Run comprehensive PR review") | .with.claude_args' "${WORKFLOW}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'--disallowedTools="Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,mcp__github_inline_comment__create_inline_comment,Read({3}/.git/**)"'* ]]
  [[ "${output}" == *'--add-dir="{2}/claude-pr-review"'* ]]
}

@test "publication uses the Claude GitHub App token" {
  # shellcheck disable=SC2016
  local expected_token='${{ steps.claude-review.outputs.github_token }}'

  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Ensure COMMENT review publication") | .env.GH_TOKEN' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "${expected_token}" ]
}

@test "Claude review context uses one bounded merge-base diff" {
  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Prepare PR review context") | .run' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  # shellcheck disable=SC2016
  [[ "${output}" == *'git diff --no-ext-diff --unified=20 "${PR_BASE_SHA}...${PR_HEAD_SHA}"'* ]]
  [[ "${output}" == *'max_diff_bytes=4194304'* ]]
  [[ "${output}" == *'head -c'* ]]
  [[ "${output}" != *'changed-files.txt'* ]]
  [[ "${output}" != *'--binary'* ]]
}

@test "pinned review plugin is adapted to the supplied diff" {
  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Prepare pinned Claude plugin marketplace") | .run' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'review_command='* ]]
  [[ "${output}" == *'review_agent='* ]]
  [[ "${output}" == *'Use the supplied PR context instead of querying GitHub'* ]]
  [[ "${output}" == *'By default, review the supplied PR diff.'* ]]
}

@test "Claude review invokes the built-in security review" {
  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Run comprehensive PR review") | .with.prompt' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Claude Code's built-in \`security-review\`"* ]]
}
