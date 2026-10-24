#!/usr/bin/env bats

setup() {
  export WORKFLOW_FILE="${BATS_TEST_DIRNAME}/../../workflows/maintenance.yml"
  export RELEASE_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/github-release.yml"
}

@test 'maintenance retains scheduled and manual tasks' {
  [ "$(yq -r '.on.schedule[0].cron' "${WORKFLOW_FILE}")" = '15 0 * * 1' ]
  [ "$(yq -r '.on.workflow_dispatch.inputs.task.default' "${WORKFLOW_FILE}")" = patch-release ]
  [ "$(yq -r '.on.workflow_dispatch.inputs.task.options | join(",")' "${WORKFLOW_FILE}")" = major-release,minor-release,patch-release,scorecard ]
}

@test 'maintenance contains no duplicated CI or empty gating jobs' {
  [ "$(yq -r '.jobs | keys | sort | join(",")' "${WORKFLOW_FILE}")" = analysis,github-release,major-version-tag,mise-lock-update ]
}

@test 'release uses direct event gating without preflight dependencies' {
  local condition
  condition="$(yq -r '.jobs."github-release".if' "${WORKFLOW_FILE}")"
  [[ "${condition}" == *"github.repository == 'dceoy/gha-for-devops'"* ]]
  [[ "${condition}" == *"github.event_name == 'schedule'"* ]]
  [[ "${condition}" == *"github.event_name == 'workflow_dispatch'"* ]]
  [[ "${condition}" == *"inputs.task != 'scorecard'"* ]]
  [ "$(yq -r '.jobs."github-release" | has("needs")' "${WORKFLOW_FILE}")" = false ]
  [ "$(yq -r '.jobs."github-release".permissions.contents' "${WORKFLOW_FILE}")" = write ]
  [ "$(yq -r '.jobs."github-release".uses' "${WORKFLOW_FILE}")" = '$/.github/workflows/github-release.yml' ]
}

@test 'weekly mise.lock update is independent of release' {
  local condition
  condition="$(yq -r '.jobs."mise-lock-update".if' "${WORKFLOW_FILE}")"
  [[ "${condition}" == *"github.repository == 'dceoy/gha-for-devops'"* ]]
  [[ "${condition}" == *"github.event_name == 'schedule'"* ]]
  [ "$(yq -r '.jobs."mise-lock-update" | has("needs")' "${WORKFLOW_FILE}")" = false ]
  [ "$(yq -r '.jobs."mise-lock-update".permissions."pull-requests"' "${WORKFLOW_FILE}")" = write ]
}

@test 'automatic release checks workflow YAML changes' {
  [ "$(yq -r '.jobs."github-release".with."version-bump"' "${WORKFLOW_FILE}")" = "\${{ inputs.task || 'auto' }}" ]
  local paths
  paths="$(yq -r '.jobs."github-release".with."release-trigger-paths"' "${WORKFLOW_FILE}")"
  [[ "${paths}" == *'.github/workflows/*.yml'* ]]
  [[ "${paths}" == *'.github/workflows/*.yaml'* ]]
  [ "$(yq -r '.on.workflow_call.inputs."release-trigger-paths".default' "${RELEASE_WORKFLOW}")" = . ]
}

@test 'major tag sync runs when the release job succeeds' {
  [ "$(yq -r '.jobs."major-version-tag".needs' "${WORKFLOW_FILE}")" = github-release ]
  [ "$(yq -r '.jobs."major-version-tag".if' "${WORKFLOW_FILE}")" = "needs.github-release.result == 'success'" ]
  [ "$(yq -r '.jobs."major-version-tag".permissions.contents' "${WORKFLOW_FILE}")" = write ]
}

@test 'Scorecard keeps its isolated permissions and triggers' {
  local condition
  condition="$(yq -r '.jobs.analysis.if' "${WORKFLOW_FILE}")"
  [[ "${condition}" == *"github.event_name == 'branch_protection_rule'"* ]]
  [[ "${condition}" == *"github.event_name == 'push'"* ]]
  [[ "${condition}" == *"inputs.task == 'scorecard'"* ]]
  [ "$(yq -r '.jobs.analysis.permissions."id-token"' "${WORKFLOW_FILE}")" = write ]
  [ "$(yq -r '.jobs.analysis.permissions."security-events"' "${WORKFLOW_FILE}")" = write ]
}

@test 'CI has no independent weekly release trigger' {
  local ci_workflow="${BATS_TEST_DIRNAME}/../../workflows/ci.yml"
  [ "$(yq -o=json '.on' "${ci_workflow}" | jq -r 'has("schedule")')" = false ]
  [ "$(yq -o=json '.jobs' "${ci_workflow}" | jq -r 'has("weekly-release")')" = false ]
}
