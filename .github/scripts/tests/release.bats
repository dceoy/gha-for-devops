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

@test 'release exposes exact file exclusions to reusable and manual calls' {
  for event in workflow_call workflow_dispatch; do
    [ "$(yq -r ".on.${event}.inputs.\"release-exclude-paths\".type" "${RELEASE_WORKFLOW}")" = string ]
  done
  [ "$(yq -r '.jobs."github-release".steps[] | select(.id == "plan") | .env.RELEASE_EXCLUDE_PATHS' "${RELEASE_WORKFLOW}")" = "\${{ inputs.release-exclude-paths }}" ]
  local excluded
  excluded="$(yq -r '.jobs."github-release".with."release-exclude-paths"' "${WORKFLOW_FILE}")"
  [ "${excluded}" = "$(printf '%s\n' .github/workflows/ai-agents.yml .github/workflows/ci.yml .github/workflows/maintenance.yml)" ]
  yq -r '.jobs."github-release".steps[] | select(.id == "plan") | .run' "${RELEASE_WORKFLOW}" | grep -Fq ':(exclude,literal)'
}

@test 'auto release ignores excluded CI workflows but includes reusable workflow changes' {
  local fixture="${BATS_TEST_TMPDIR}/release-repo"
  local bin="${BATS_TEST_TMPDIR}/bin"
  local plan_script="${BATS_TEST_TMPDIR}/release-plan.sh"
  mkdir -p "${fixture}/.github/workflows" "${bin}"
  yq -r '.jobs."github-release".steps[] | select(.id == "plan") | .run' "${RELEASE_WORKFLOW}" > "${plan_script}"
  cat > "${bin}/gh" << 'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  'api repos/example/test/git/ref/heads/main')
    echo "${RELEASE_SHA}"
    ;;
  'release list')
    echo v1.2.3
    ;;
  *)
    echo "Unexpected gh invocation: $*" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "${bin}/gh"
  cd "${fixture}" || exit 1
  git init -q -b main
  git config user.email ci@example.invalid
  git config user.name 'Release test'
  for name in ai-agents.yml ci.yml maintenance.yml reusable.yml; do
    printf 'on:\n  workflow_call:\n' > ".github/workflows/${name}"
  done
  git add .
  git commit -qm 'ci: baseline'
  git tag v1.2.3
  for name in ai-agents.yml ci.yml maintenance.yml; do
    echo '# changed' >> ".github/workflows/${name}"
  done
  git add .
  git commit -qm 'fix: adjust CI triggers'
  export GITHUB_REF=refs/heads/main
  export GITHUB_REPOSITORY=example/test
  export RELEASE_BUMP=auto
  export RELEASE_PATHS=$'.github/workflows/*.yml\n.github/workflows/*.yaml'
  export RELEASE_EXCLUDE_PATHS
  RELEASE_EXCLUDE_PATHS="$(yq -r '.jobs."github-release".with."release-exclude-paths"' "${WORKFLOW_FILE}")"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/release-output"
  export PATH="${bin}:${PATH}"
  export RELEASE_SHA
  RELEASE_SHA="$(git rev-parse HEAD)"
  : > "${GITHUB_OUTPUT}"
  run bash -euo pipefail "${plan_script}"
  [ "${status}" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
  [[ "${output}" == *'No changes to the configured release paths.'* ]]

  : > "${GITHUB_OUTPUT}"
  run env RELEASE_EXCLUDE_PATHS= bash -euo pipefail "${plan_script}"
  [ "${status}" -eq 0 ]
  grep -qx 'ready=true' "${GITHUB_OUTPUT}"
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"

  echo '# changed' >> .github/workflows/reusable.yml
  git add .
  git commit -qm 'fix: update reusable workflow'
  RELEASE_SHA="$(git rev-parse HEAD)"
  : > "${GITHUB_OUTPUT}"
  run bash -euo pipefail "${plan_script}"
  [ "${status}" -eq 0 ]
  grep -qx 'ready=true' "${GITHUB_OUTPUT}"
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
}
