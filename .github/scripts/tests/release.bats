#!/usr/bin/env bats

setup() {
  export WORKFLOW_FILE="${BATS_TEST_DIRNAME}/../../workflows/maintenance.yml"
  export RELEASE_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/github-release.yml"
}

@test 'maintenance retains scheduled and manual tasks' {
  [ "$(yq -r '.on.schedule[0].cron' "${WORKFLOW_FILE}")" = '15 0 * * 1' ]
  [ "$(yq -r '.on.workflow_dispatch.inputs.task.default' "${WORKFLOW_FILE}")" = patch-release ]
  [ "$(yq -r '.on.workflow_dispatch.inputs.task.options | join(",")' "${WORKFLOW_FILE}")" = major-release,minor-release,patch-release,scorecard,mise-lock-upgrade,dependencies-upgrade ]
}

@test 'maintenance retains the Bats regression job alongside release and Scorecard' {
  [ "$(yq -r '.jobs | keys | sort | join(",")' "${WORKFLOW_FILE}")" = analysis,bats-tests,github-release,major-version-tag,mise-lock-update,renovate-dependencies ]
}

@test 'scheduled maintenance runs full scanner E2E without release gating' {
  local condition
  condition="$(yq -r '.jobs."bats-tests".if' "${WORKFLOW_FILE}")"
  [[ "${condition}" == *"github.event_name == 'schedule'"* ]]
  [[ "${condition}" != *"workflow_dispatch"* ]]
  [ "$(yq -r '.jobs."bats-tests" | has("needs")' "${WORKFLOW_FILE}")" = false ]
  [ "$(yq -r '.jobs."bats-tests".steps[] | select(.name == "Run Bats tests") | .run' "${WORKFLOW_FILE}")" = 'bats --print-output-on-failure .github/scripts/tests/*.bats' ]
}

@test 'single release job gates schedule on Bats and analysis but permits manual release' {
  local condition
  condition="$(yq -r '.jobs."github-release".if' "${WORKFLOW_FILE}")"
  [[ "${condition}" == *"!cancelled()"* ]]
  [[ "${condition}" == *"github.repository == 'dceoy/gha-for-devops'"* ]]
  [[ "${condition}" == *"github.event_name == 'schedule'"* ]]
  [[ "${condition}" == *"needs.bats-tests.result == 'success'"* ]]
  [[ "${condition}" == *"needs.analysis.result == 'success'"* ]]
  [[ "${condition}" == *"github.event_name == 'workflow_dispatch'"* ]]
  [[ "${condition}" == *"inputs.task != 'scorecard'"* ]]
  [[ "${condition}" == *"inputs.task != 'mise-lock-upgrade'"* ]]
  [[ "${condition}" == *"inputs.task != 'dependencies-upgrade'"* ]]
  [ "$(yq -r '.jobs."github-release".needs | sort | join(",")' "${WORKFLOW_FILE}")" = analysis,bats-tests ]
  [ "$(yq -r '.jobs."github-release".permissions.contents' "${WORKFLOW_FILE}")" = write ]
  [ "$(yq -r '.jobs."github-release".uses' "${WORKFLOW_FILE}")" = '$/.github/workflows/github-release.yml' ]
  [ "$(yq -r '.jobs | has("github-release-manual")' "${WORKFLOW_FILE}")" = false ]
}

@test 'mise.lock update is manual-only and independent of release' {
  local condition
  condition="$(yq -r '.jobs."mise-lock-update".if' "${WORKFLOW_FILE}")"
  [[ "${condition}" == *"github.repository == 'dceoy/gha-for-devops'"* ]]
  [[ "${condition}" == *"github.event_name == 'workflow_dispatch'"* ]]
  [[ "${condition}" == *"inputs.task == 'mise-lock-upgrade'"* ]]
  [[ "${condition}" != *"github.event_name == 'schedule'"* ]]
  [ "$(yq -r '.jobs."mise-lock-update" | has("needs")' "${WORKFLOW_FILE}")" = false ]
  [ "$(yq -r '.jobs."mise-lock-update".permissions."pull-requests"' "${WORKFLOW_FILE}")" = write ]
  [ "$(yq -r '.jobs."mise-lock-update".uses' "${WORKFLOW_FILE}")" = '$/.github/workflows/mise-lock-update.yml' ]
  local group
  group="$(yq -r '.concurrency.group' "${WORKFLOW_FILE}")"
  [[ "${group}" == *"inputs.task == 'mise-lock-upgrade'"* ]]
}

@test 'Renovate lockfile maintenance is manual-only and independent of release' {
  local condition renovation config
  condition="$(yq -r '.jobs."renovate-dependencies".if' "${WORKFLOW_FILE}")"
  [[ "${condition}" == *"inputs.task == 'dependencies-upgrade'"* ]]
  [[ "${condition}" == *"github.event_name == 'workflow_dispatch'"* ]]
  [[ "${condition}" != *"github.event_name == 'schedule'"* ]]
  [ "$(yq -r '.jobs."renovate-dependencies".uses' "${WORKFLOW_FILE}")" = '$/.github/workflows/renovate.yml' ]
  [ "$(yq -r '.jobs."renovate-dependencies".permissions."pull-requests"' "${WORKFLOW_FILE}")" = write ]
  [ "$(yq -r '.jobs."renovate-dependencies".with."allowed-unsafe-executions"' "${WORKFLOW_FILE}")" = '["mise"]' ]
  renovation="${BATS_TEST_DIRNAME}/../../workflows/renovate.yml"
  [ "$(yq -r '.on.workflow_call.secrets.GH_TOKEN.required' "${renovation}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."allowed-unsafe-executions".type' "${renovation}")" = string ]
  [ "$(yq -r '.on.workflow_call.inputs."allowed-unsafe-executions".default' "${renovation}")" = '[]' ]
  [ "$(yq -r '.on.workflow_dispatch.inputs."allowed-unsafe-executions".type' "${renovation}")" = string ]
  [ "$(yq -r '.on.workflow_dispatch.inputs."allowed-unsafe-executions".default' "${renovation}")" = '[]' ]
  [ "$(yq -r '.on.workflow_call.inputs | has("dry-run")' "${renovation}")" = false ]
  [ "$(yq -r '.on.workflow_dispatch.inputs | has("dry-run")' "${renovation}")" = false ]
  [ "$(yq -r '.jobs.renovate | has("timeout-minutes")' "${renovation}")" = false ]
  [ "$(yq -r '.jobs.renovate.steps[] | select(.name == "Run Renovate") | .env.RENOVATE_ALLOWED_UNSAFE_EXECUTIONS' "${renovation}")" = "\${{ inputs.allowed-unsafe-executions }}" ]
  config="${BATS_TEST_DIRNAME}/../../../.github/renovate.json"
  [ "$(jq -r '.extends | index("group:all") != null' "${config}")" = true ]
  [ "$(jq -r '.lockFileMaintenance.groupName' "${config}")" = 'All dependency lockfiles' ]
  [ "$(jq -r '.lockFileMaintenance.schedule | join(",")' "${config}")" = 'at any time' ]
  jq -e '.packageRules | any(.[]; .matchUpdateTypes == ["lockFileMaintenance"] and .automerge == false and .minimumReleaseAge == null)' "${config}" > /dev/null
  jq -e '.packageRules | any(.[]; .matchManagers == ["npm","pep621"] and .enabled == false and (.matchUpdateTypes | index("lockFileMaintenance") | not))' "${config}" > /dev/null
}

@test 'automatic and manual releases use a shared job with the appropriate bump' {
  [ "$(yq -r '.jobs."github-release".with."version-bump"' "${WORKFLOW_FILE}")" = "\${{ inputs.task || 'auto' }}" ]
  local paths
  paths="$(yq -r '.jobs."github-release".with."release-trigger-paths"' "${WORKFLOW_FILE}")"
  [[ "${paths}" == *'.github/workflows/*.yml'* ]]
  [[ "${paths}" == *'.github/workflows/*.yaml'* ]]
  [ "$(yq -r '.on.workflow_call.inputs."release-trigger-paths".default' "${RELEASE_WORKFLOW}")" = . ]
}

@test 'major tag sync runs only when the single release succeeds' {
  [ "$(yq -r '.jobs."major-version-tag".needs' "${WORKFLOW_FILE}")" = github-release ]
  [ "$(yq -r '.jobs."major-version-tag".if' "${WORKFLOW_FILE}")" = "needs.github-release.result == 'success'" ]
  [ "$(yq -r '.jobs."major-version-tag".permissions.contents' "${WORKFLOW_FILE}")" = write ]
  [ "$(yq -r '.jobs | has("major-version-tag-manual")' "${WORKFLOW_FILE}")" = false ]
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

@test 'release supports ! path exclusions through a single input' {
  for event in workflow_call workflow_dispatch; do
    [ "$(yq -r ".on.${event}.inputs.\"release-trigger-paths\".type" "${RELEASE_WORKFLOW}")" = string ]
    [ "$(yq -r ".on.${event}.inputs | has(\"release-exclude-paths\")" "${RELEASE_WORKFLOW}")" = false ]
  done
  [ "$(yq -r '.jobs."github-release".steps[] | select(.id == "plan") | .env | has("RELEASE_EXCLUDE_PATHS")' "${RELEASE_WORKFLOW}")" = false ]
  local paths
  paths="$(yq -r '.jobs."github-release".with."release-trigger-paths"' "${WORKFLOW_FILE}")"
  [ "${paths}" = "$(printf '%s\n' '.github/workflows/*.yml' '.github/workflows/*.yaml' '!.github/workflows/ai-agents.yml' '!.github/workflows/ci.yml' '!.github/workflows/maintenance.yml')" ]
  yq -r '.jobs."github-release".steps[] | select(.id == "plan") | .run' "${RELEASE_WORKFLOW}" | grep -Fq ':(exclude)'
}

@test 'auto release respects ! exclusion patterns and reusable workflow changes' {
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
  export RELEASE_PATHS
  RELEASE_PATHS="$(yq -r '.jobs."github-release".with."release-trigger-paths"' "${WORKFLOW_FILE}")"
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
  run env RELEASE_PATHS='.github/workflows/*.yml' bash -euo pipefail "${plan_script}"
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

  : > "${GITHUB_OUTPUT}"
  run env RELEASE_PATHS=$'.github/workflows/reusable.yml\n!.github/workflows/reus*.yml' bash -euo pipefail "${plan_script}"
  [ "${status}" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]

  : > "${GITHUB_OUTPUT}"
  run env RELEASE_PATHS='!' bash -euo pipefail "${plan_script}"
  [ "${status}" -eq 2 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
  [[ "${output}" == *'empty exclusion'* ]]
}

run_release_publish() {
  local bin="${BATS_TEST_TMPDIR}/bin"
  local publish_script="${BATS_TEST_TMPDIR}/release-publish.sh"
  mkdir -p "${bin}"
  yq -r '.jobs."github-release".steps[] | select(.id == "publish") | .run' "${RELEASE_WORKFLOW}" > "${publish_script}"
  cat > "${bin}/gh" << 'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_CALLS}"
case "$1 $2" in
  'release view')
    if [[ -n "${MOCK_EXISTING_RELEASE:-}" ]]; then
      exit 0
    fi
    exit 1
    ;;
  'api repos/example/test/git/ref/heads/main')
    printf '%s\n' "${MOCK_BRANCH_SHA:-0123456789abcdef0123456789abcdef01234567}"
    ;;
  'api repos/example/test/git/matching-refs/tags/v1.0.0')
    if [[ -n "${MOCK_EXISTING_TAG:-}" ]]; then
      echo refs/tags/v1.0.0
    fi
    ;;
  'api repos/example/test/commits/v1.0.0')
    printf '%s\n' "${MOCK_TAG_SHA:-0123456789abcdef0123456789abcdef01234567}"
    ;;
  'api repos/example/test/git/refs' | 'release create') ;;
  *)
    echo "Unexpected gh invocation: $*" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "${bin}/gh"
  export GH_CALLS="${BATS_TEST_TMPDIR}/gh-calls"
  RELEASE_OUTPUT="${BATS_TEST_TMPDIR}/publish-output"
  : > "${GH_CALLS}"
  : > "${RELEASE_OUTPUT}"
  local base_path
  base_path="$(printenv PATH)"
  run env PATH="${bin}:${base_path}" GITHUB_OUTPUT="${RELEASE_OUTPUT}" \
    GITHUB_REF=refs/heads/main GITHUB_REF_NAME=main GITHUB_REPOSITORY=example/test REPOSITORY=example/test \
    TAG_NAME=v1.0.0 SOURCE_BRANCH='' PLANNED_TAG='' PREVIOUS_TAG='' RELEASE_BUMP=auto CREATE_NEW_TAG=true \
    RELEASE_SHA=0123456789abcdef0123456789abcdef01234567 "$@" \
    bash -euo pipefail "${publish_script}"
}

@test 'draft release creates the tag before the draft release' {
  run_release_publish RELEASE_DRAFT=true
  [ "${status}" -eq 0 ]
  grep -Fxq 'api repos/example/test/git/refs --method POST -f ref=refs/tags/v1.0.0 -f sha=0123456789abcdef0123456789abcdef01234567' "${GH_CALLS}"
  grep -Fxq 'release create v1.0.0 --repo example/test --generate-notes --draft --verify-tag' "${GH_CALLS}"
  grep -Fxq 'tag=v1.0.0' "${RELEASE_OUTPUT}"
}

@test 'release keeps non-draft tag creation by default' {
  run_release_publish RELEASE_DRAFT=false
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'git/' "${GH_CALLS}")" -eq 0 ]
  grep -Fxq 'release create v1.0.0 --repo example/test --generate-notes' "${GH_CALLS}"
  grep -Fxq 'tag=v1.0.0' "${RELEASE_OUTPUT}"
}

@test 'explicit draft tag is created when the source branch tip still matches' {
  run_release_publish RELEASE_DRAFT=true SOURCE_BRANCH=main
  [ "${status}" -eq 0 ]
  grep -Fxq 'api repos/example/test/git/ref/heads/main --jq .object.sha' "${GH_CALLS}"
  grep -Fxq 'api repos/example/test/git/refs --method POST -f ref=refs/tags/v1.0.0 -f sha=0123456789abcdef0123456789abcdef01234567' "${GH_CALLS}"
  grep -Fxq 'tag=v1.0.0' "${RELEASE_OUTPUT}"
}

@test 'explicit draft tag is refused when the source branch advanced' {
  run_release_publish RELEASE_DRAFT=true SOURCE_BRANCH=main MOCK_BRANCH_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'refusing to continue the release for a stale commit'* ]]
  [ "$(grep -c 'git/refs' "${GH_CALLS}")" -eq 0 ]
  [ "$(grep -c 'release create' "${GH_CALLS}")" -eq 0 ]
  [ ! -s "${RELEASE_OUTPUT}" ]
}

@test 'existing explicit draft tag is refused when the source branch advanced' {
  run_release_publish RELEASE_DRAFT=true SOURCE_BRANCH=main MOCK_EXISTING_TAG=1 MOCK_BRANCH_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'refusing to continue the release for a stale commit'* ]]
  [ "$(grep -c 'release create' "${GH_CALLS}")" -eq 0 ]
  [ ! -s "${RELEASE_OUTPUT}" ]
}

@test 'existing explicit draft tag is reused when it matches and the source branch is current' {
  run_release_publish RELEASE_DRAFT=true SOURCE_BRANCH=main MOCK_EXISTING_TAG=1
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'git/refs' "${GH_CALLS}")" -eq 0 ]
  grep -Fxq 'release create v1.0.0 --repo example/test --generate-notes --draft --verify-tag' "${GH_CALLS}"
  grep -Fxq 'tag=v1.0.0' "${RELEASE_OUTPUT}"
}

@test 'existing explicit draft tag is refused when it resolves to another commit' {
  run_release_publish RELEASE_DRAFT=true SOURCE_BRANCH=main MOCK_EXISTING_TAG=1 MOCK_TAG_SHA=cccccccccccccccccccccccccccccccccccccccc
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'refusing to continue the release for another commit'* ]]
  [ "$(grep -c 'release create' "${GH_CALLS}")" -eq 0 ]
  [ ! -s "${RELEASE_OUTPUT}" ]
}

@test 'existing draft release is refused when the source branch advanced' {
  run_release_publish RELEASE_DRAFT=true SOURCE_BRANCH=main MOCK_EXISTING_TAG=1 MOCK_EXISTING_RELEASE=1 MOCK_BRANCH_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'refusing to continue the release for a stale commit'* ]]
  [ "$(grep -c 'release create' "${GH_CALLS}")" -eq 0 ]
  [ ! -s "${RELEASE_OUTPUT}" ]
}

@test 'existing draft release is refused when its tag resolves to another commit' {
  run_release_publish RELEASE_DRAFT=true SOURCE_BRANCH=main MOCK_EXISTING_TAG=1 MOCK_EXISTING_RELEASE=1 MOCK_TAG_SHA=cccccccccccccccccccccccccccccccccccccccc
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'refusing to continue the release for another commit'* ]]
  [ ! -s "${RELEASE_OUTPUT}" ]
}

@test 'existing draft release is reused when the source branch and tag are current' {
  run_release_publish RELEASE_DRAFT=true SOURCE_BRANCH=main MOCK_EXISTING_TAG=1 MOCK_EXISTING_RELEASE=1
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'release create' "${GH_CALLS}")" -eq 0 ]
  [ "$(grep -c 'git/refs' "${GH_CALLS}")" -eq 0 ]
  grep -Fxq 'tag=v1.0.0' "${RELEASE_OUTPUT}"
}
