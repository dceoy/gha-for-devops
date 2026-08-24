#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/claude-code-review.yml"
  TEST_TEMP="$(mktemp -d)"
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

run_diagnosis() {
  local step_script="${TEST_TEMP}/diagnose-claude-review.sh"

  extract_step "Diagnose Claude Code failure" "${step_script}"
  run env \
    CLAUDE_EXECUTION_FILE="${CLAUDE_EXECUTION_FILE:-}" \
    CLAUDE_REVIEW_CONCLUSION="${CLAUDE_REVIEW_CONCLUSION}" \
    CLAUDE_REVIEW_OUTCOME="${CLAUDE_REVIEW_OUTCOME}" \
    bash -euo pipefail "${step_script}"
}

@test "Claude review restores the default tool set without a deny list" {
  run yq -r '.on.workflow_call.inputs."claude-args".default' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'Bash(gh:*)'* ]]
  [[ "${output}" == *'Bash(git:*)'* ]]
  [[ "${output}" == *'WebFetch'* ]]
  [[ "${output}" == *'WebSearch'* ]]
  [[ "${output}" == *'mcp__github_inline_comment__create_inline_comment'* ]]

  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Run comprehensive PR review") | .with.claude_args' "${WORKFLOW}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'--disallowedTools'* ]]
}

@test "workflow and Claude App keep contents read-only while allowing PR reviews" {
  run yq -r '.permissions.contents' "${WORKFLOW}"
  [ "${output}" = read ]

  run yq -r '.permissions."pull-requests"' "${WORKFLOW}"
  [ "${output}" = write ]

  run yq -r '.permissions."id-token"' "${WORKFLOW}"
  [ "${output}" = write ]

  run yq -r '.defaults.run."working-directory"' "${WORKFLOW}"
  [ "${output}" = . ]

  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Run comprehensive PR review") | .with.additional_permissions' "${WORKFLOW}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'contents: read'* ]]
  [[ "${output}" == *'pull_requests: write'* ]]
  [[ "${output}" == *'issues: read'* ]]
  [[ "${output}" == *'actions: read'* ]]
}

@test "Claude Code action publishes the PR review directly" {
  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Run comprehensive PR review") | .with.prompt' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'mcp__github_inline_comment__create_inline_comment'* ]]
  [[ "${output}" == *'gh pr review '* ]]
  [[ "${output}" == *'--comment'* ]]
  [[ "${output}" == *'Publishing the review is a required part of this task'* ]]
  [[ "${output}" == *'gh api repos/${{ github.repository }}/pulls/${{ github.event.pull_request.number }}/reviews'* ]]
  [[ "${output}" == *'Do not return a final response until publication is verified'* ]]

  run yq -r '[.jobs."claude-code-review".steps[] | select(.name == "Ensure COMMENT review publication")] | length' "${WORKFLOW}"
  [ "${output}" -eq 0 ]
}

@test "Claude Code action uses its GitHub App token" {
  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Run comprehensive PR review") | .with.github_token // ""' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "review plugin marketplace stays pinned without runtime rewriting" {
  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Prepare pinned Claude plugin marketplace") | .run' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'CLAUDE_PLUGINS_REF'* ]]
  [[ "${output}" != *'sed -i'* ]]
  [[ "${output}" != *'review_command='* ]]
}

@test "Claude review invokes the built-in security review" {
  run yq -r '.jobs."claude-code-review".steps[] | select(.name == "Run comprehensive PR review") | .with.prompt' "${WORKFLOW}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Claude Code's built-in \`security-review\`"* ]]
}

@test "diagnosis leaves a successful Claude review untouched" {
  CLAUDE_REVIEW_OUTCOME=success
  CLAUDE_REVIEW_CONCLUSION=success
  export CLAUDE_REVIEW_OUTCOME CLAUDE_REVIEW_CONCLUSION

  run_diagnosis

  [ "${status}" -eq 0 ]
}

@test "diagnosis fails for a non-success Claude result" {
  CLAUDE_REVIEW_OUTCOME=success
  CLAUDE_REVIEW_CONCLUSION=failure
  CLAUDE_EXECUTION_FILE="${TEST_TEMP}/execution.json"
  printf '%s\n' '[{"type":"result","subtype":"error","is_error":true,"errors":["boom"]}]' > "${CLAUDE_EXECUTION_FILE}"
  export CLAUDE_REVIEW_OUTCOME CLAUDE_REVIEW_CONCLUSION CLAUDE_EXECUTION_FILE

  run_diagnosis

  [ "${status}" -ne 0 ]
  [[ "${output}" == *'"errors":["boom"]'* ]]
}
