#!/usr/bin/env bats

setup() {
  export WORKFLOW_FILE="${BATS_TEST_DIRNAME}/../../workflows/maintenance.yml"
  export RELEASE_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/github-release.yml"
}

@test 'maintenance retains scheduled and manual release triggers' {
  [ "$(yq -r '.on.schedule[0].cron' "${WORKFLOW_FILE}")" = '15 0 * * 1' ]
  [ "$(yq -r '.on.workflow_dispatch.inputs.task.default' "${WORKFLOW_FILE}")" = patch-release ]
  [ "$(yq -r '.on.workflow_dispatch.inputs.task.options | join(",")' "${WORKFLOW_FILE}")" = major-release,minor-release,patch-release,scorecard ]
}

@test 'Scorecard triggers do not schedule release preflight' {
  gate="$(yq -r '.jobs."release-gate".if' "${WORKFLOW_FILE}")"
  [[ "${gate}" == *"github.repository == 'dceoy/gha-for-devops'"* ]]
  [[ "${gate}" == *"github.event_name == 'schedule'"* ]]
  [[ "${gate}" == *"inputs.task != 'scorecard'"* ]]
  [ "$(yq -r '.jobs.analysis.permissions."id-token"' "${WORKFLOW_FILE}")" = write ]
  [ "$(yq -r '.jobs.analysis.permissions."security-events"' "${WORKFLOW_FILE}")" = write ]
}

@test 'release preflight gates all validation jobs' {
  local job
  for job in mise-lock-update shell-lint markdown-lint github-actions-lint-and-scan bats-tests; do
    [ "$(yq -r ".jobs.\"${job}\".needs" "${WORKFLOW_FILE}")" = release-gate ]
  done
}

@test 'release only runs after all validation jobs succeed' {
  [ "$(yq -r '.jobs."github-release".needs | join(",")' "${WORKFLOW_FILE}")" = release-gate,mise-lock-update,shell-lint,markdown-lint,github-actions-lint-and-scan,bats-tests ]
  [ "$(yq -r '.jobs."github-release".permissions.contents' "${WORKFLOW_FILE}")" = write ]
  [ "$(yq -r '.jobs."github-release".uses' "${WORKFLOW_FILE}")" = '$/.github/workflows/github-release.yml' ]
}

@test 'file-based release detection uses only workflow YAML files' {
  [ "$(yq -r '.jobs."github-release".with."version-bump"' "${WORKFLOW_FILE}")" = "\${{ inputs.task || 'auto' }}" ]
  paths="$(yq -r '.jobs."github-release".with."release-trigger-paths"' "${WORKFLOW_FILE}")"
  [[ "${paths}" == *'.github/workflows/*.yml'* ]]
  [[ "${paths}" == *'.github/workflows/*.yaml'* ]]
  [ "$(yq -r '.on.workflow_call.inputs."release-trigger-paths".default' "${RELEASE_WORKFLOW}")" = . ]
  ! grep -Fq 'release.sh' "${WORKFLOW_FILE}"
}

@test 'major tag sync runs after successful release job even when no new tag is needed' {
  [ "$(yq -r '.jobs."major-version-tag".needs' "${WORKFLOW_FILE}")" = github-release ]
  [ "$(yq -r '.jobs."major-version-tag".if' "${WORKFLOW_FILE}")" = "needs.github-release.result == 'success'" ]
  [ "$(yq -r '.jobs."major-version-tag".permissions.contents' "${WORKFLOW_FILE}")" = write ]
}

@test 'CI has no independent weekly release trigger' {
  local ci_workflow="${BATS_TEST_DIRNAME}/../../workflows/ci.yml"
  [ "$(yq -o=json '.on' "${ci_workflow}" | jq -r 'has("schedule")')" = false ]
  [ "$(yq -o=json '.jobs' "${ci_workflow}" | jq -r 'has("weekly-release")')" = false ]
}
