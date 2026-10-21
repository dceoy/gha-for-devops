#!/usr/bin/env bats

setup() {
  # Test the repository release script through its plan and publish entry points.
  export WORKFLOW_FILE="${BATS_TEST_DIRNAME}/../../workflows/maintenance.yml"
  export RELEASE_SCRIPT="${BATS_TEST_DIRNAME}/../weekly-release.sh"
  export PLAN_SCRIPT="${BATS_TEST_TMPDIR}/plan.sh"
  export PUBLISH_SCRIPT="${BATS_TEST_TMPDIR}/publish.sh"
  printf 'exec bash "%s" plan\n' "${RELEASE_SCRIPT}" > "${PLAN_SCRIPT}"
  printf 'exec bash "%s" publish\n' "${RELEASE_SCRIPT}" > "${PUBLISH_SCRIPT}"
  export TEST_DIR="${BATS_TEST_TMPDIR}/candidate"
  mkdir -p "${TEST_DIR}/.github/workflows" "${TEST_DIR}/.github/scripts"
  cd "${TEST_DIR}" || exit
  bash -n "${RELEASE_SCRIPT}" "${PLAN_SCRIPT}" "${PUBLISH_SCRIPT}"
  git init -q -b main
  git config user.email ci@example.invalid
  git config user.name 'Release test'
  printf 'on:\n  workflow_call:\njobs: {}\n' > .github/workflows/reusable.yml
  git add .
  git commit -qm 'ci: baseline'
  git tag v1.2.3
  echo '# update' >> .github/workflows/reusable.yml
  git add .
  git commit -qm 'fix: update reusable workflow'

  export RELEASE_SHA
  RELEASE_SHA="$(git rev-parse HEAD)"
  export GITHUB_REPOSITORY='example/test'
  export GITHUB_REF='refs/heads/main'
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output"
  export FAKE_STATE="${BATS_TEST_TMPDIR}/github"
  mkdir -p "${FAKE_STATE}"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/gh" << 'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  'api repos/example/test/git/ref/heads/main')
    if [[ "${FAKE_MAIN_ERROR:-false}" == true ]]; then
      echo 'GitHub API error' >&2
      exit 1
    fi
    printf '%s\n' "${FAKE_HEAD:-${RELEASE_SHA}}"
    ;;
  'api repos/example/test/git/matching-refs/'*)
    if [[ "${FAKE_REMOTE_ERROR:-false}" == true ]]; then
      echo 'GitHub API error' >&2
      exit 1
    fi
    if [[ -f "${FAKE_STATE}/tag" ]]; then
      cat "${FAKE_STATE}/tag"
    else
      printf '%s\n' "${FAKE_REMOTE_TAG:-}"
    fi
    ;;
  'release list')
    printf '%s\n' "${FAKE_LATEST:-v1.2.3}"
    ;;
  'api repos/example/test/releases')
    if [[ "${FAKE_RELEASE_ERROR:-false}" == true ]]; then
      echo 'GitHub API error' >&2
      exit 1
    fi
    printf '%s\n' "${FAKE_EXISTING_RELEASE:-}"
    ;;
  'api repos/example/test/git/refs')
    echo tag-create >> "${FAKE_STATE}/mutations"
    printf 'commit\t%s\n' "${RELEASE_SHA}" > "${FAKE_STATE}/tag"
    ;;
  'release create')
    echo release-create >> "${FAKE_STATE}/mutations"
    if [[ "${FAKE_CREATE_ERROR:-false}" == true ]]; then
      echo 'Release creation failed' >&2
      exit 1
    fi
    ;;
  *)
    echo "Unexpected gh invocation: $*" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
}

@test 'weekly release executes the repository script' {
  [ "$(yq -r '.jobs.plan.steps[] | select(.id == "plan") | .run' "${WORKFLOW_FILE}")" = 'bash .github/scripts/weekly-release.sh plan' ]
  [ "$(yq -r '.jobs.publish.steps[] | select(.id == "publish") | .run' "${WORKFLOW_FILE}")" = 'bash .github/scripts/weekly-release.sh publish' ]
}

@test 'repository maintenance routes scheduled and manual jobs independently' {
  [ "$(yq -r '.on.schedule[0].cron' "${WORKFLOW_FILE}")" = '15 0 * * 1' ]
  [ "$(yq -r '.on.schedule | length' "${WORKFLOW_FILE}")" -eq 1 ]
  [ "$(yq -r '.on.workflow_dispatch.inputs.task.default' "${WORKFLOW_FILE}")" = patch-release ]
  [ "$(yq -r '.on.workflow_dispatch.inputs.task.options | join(",")' "${WORKFLOW_FILE}")" = major-release,minor-release,patch-release,scorecard ]
  grep -Fq "github.event.schedule == '15 0 * * 1'" "${WORKFLOW_FILE}"
  for task in major-release minor-release patch-release; do
    grep -Fq "inputs.task == '${task}'" < <(yq -r '.jobs.plan.if' "${WORKFLOW_FILE}")
    grep -Fq "inputs.task == '${task}'" < <(yq -r '.concurrency.group' "${WORKFLOW_FILE}")
  done
  [ "$(yq -r '.jobs.plan.steps[] | select(.id == "plan") | .env.RELEASE_BUMP' "${WORKFLOW_FILE}")" = "\${{ github.event_name == 'workflow_dispatch' && inputs.task || 'auto' }}" ]
  [ "$(yq -r '.jobs.analysis.if' "${WORKFLOW_FILE}" | grep -c "inputs.task == 'scorecard'")" -eq 1 ]
  yq -r '.jobs.analysis.if' "${WORKFLOW_FILE}" | grep -Fq "github.event_name == 'schedule'"
}

@test 'CI no longer calls or schedules weekly releases' {
  local ci_workflow="${BATS_TEST_DIRNAME}/../../workflows/ci.yml"
  [ "$(yq -o=json '.on' "${ci_workflow}" | jq -r 'has("schedule")')" = false ]
  [ "$(yq -o=json '.jobs' "${ci_workflow}" | jq -r 'has("weekly-release")')" = false ]
  [ "$(yq -o=json '.on.workflow_dispatch.inputs.workflow.options' "${ci_workflow}" | jq -r 'index("weekly-release")')" = null ]
}

@test 'YAML parser is installed from the repository mise configuration' {
  local setup_inputs
  setup_inputs="$(yq -o=json '.jobs.plan.steps[] | select(.name == "Set up YAML parser") | .with' "${WORKFLOW_FILE}")"
  [ "$(jq -r '.install_args' <<< "${setup_inputs}")" = yq ]
  [ "$(jq -r 'has("working_directory")' <<< "${setup_inputs}")" = false ]
  [ "$(jq -r 'has("mise_toml")' <<< "${setup_inputs}")" = false ]
  [ "$(yq -r '[.jobs.plan.steps[] | select(.name == "Add pinned YAML parser to PATH")] | length' "${WORKFLOW_FILE}")" = 0 ]
  grep -qx 'yq = "latest"' "${BATS_TEST_DIRNAME}/../../../mise.toml"
}

@test 'manual major release plans the next major version' {
  run env RELEASE_BUMP=major-release bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'ready=true' "${GITHUB_OUTPUT}"
  grep -qx 'tag=v2.0.0' "${GITHUB_OUTPUT}"
}

@test 'manual major release works without reusable workflow changes' {
  git reset -q --hard v1.2.3
  echo documentation > README.md
  git add .
  git commit -qm 'docs: no workflow changes'
  run env RELEASE_BUMP=major-release "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'ready=true' "${GITHUB_OUTPUT}"
  grep -qx 'tag=v2.0.0' "${GITHUB_OUTPUT}"
}

@test 'manual major release rejects conflicting version tags' {
  git tag v2.0.0 v1.2.3
  run env RELEASE_BUMP=major-release bash "${PLAN_SCRIPT}"
  [ "$status" -ne 0 ]
  [[ "$output" == *'already exists locally'* ]]
}

@test 'manual minor release plans the next minor version' {
  run env RELEASE_BUMP=minor-release bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'ready=true' "${GITHUB_OUTPUT}"
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'manual patch release plans the next patch version' {
  run env RELEASE_BUMP=patch-release bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'ready=true' "${GITHUB_OUTPUT}"
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
}

@test 'manual minor and patch releases do not require workflow changes' {
  git reset -q --hard v1.2.3
  echo documentation > README.md
  git add .
  git commit -qm 'docs: no reusable changes'
  local bump expected
  for bump in minor-release patch-release; do
    : > "${GITHUB_OUTPUT}"
    expected=v1.3.0
    if [[ "${bump}" == patch-release ]]; then
      expected=v1.2.4
    fi
    run env RELEASE_BUMP="${bump}" "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -qx 'ready=true' "${GITHUB_OUTPUT}"
    grep -qx "tag=${expected}" "${GITHUB_OUTPUT}"
  done
}

@test 'manual release bump rejects unknown types' {
  run env RELEASE_BUMP=invalid bash "${PLAN_SCRIPT}"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Invalid release bump'* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test 'patch release is planned without requiring an earlier push CI run' {
  run bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'ready=true' "${GITHUB_OUTPUT}"
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
}

@test 'a documentation-only commit has no release' {
  git reset -q --hard v1.2.3
  echo 'documentation' > README.md
  git add .
  git commit -qm 'docs: documentation'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'sync-major=true' "${GITHUB_OUTPUT}"
}

@test 'a feature in a squash commit body increments minor' {
  git commit --amend -qm 'fix: bundle changes' -m '* feat(workflows): add a workflow'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'breaking changes in squash body increment minor' {
  git commit --amend -qm 'fix: bundled change' -m '* feat!: remove input'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'BREAKING-CHANGE footer increments minor' {
  git commit --amend -qm 'fix: bundled change' -m '  BREAKING-CHANGE: removed inputs'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'breaking fix commit increments minor instead of patch' {
  git commit --amend -qm 'fix!: change an existing workflow input'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'BREAKING CHANGE footer increments minor' {
  git commit --amend -qm 'fix: remove old input' -m 'BREAKING CHANGE: removed old input'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'regular CI workflow changes do not trigger a release' {
  git reset -q --hard v1.2.3
  printf 'on:\n  push:\njobs: {}\n' > .github/workflows/ci.yml
  git add .
  git commit -qm 'ci: update regular workflow'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'sync-major=true' "${GITHUB_OUTPUT}"
}

@test 'composite action changes alone do not trigger a release' {
  git reset -q --hard v1.2.3
  mkdir -p .github/actions/local
  printf 'name: local\nruns:\n  using: composite\n  steps: []\n' > .github/actions/local/action.yml
  git add .
  git commit -qm 'fix: adjust composite action'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'sync-major=true' "${GITHUB_OUTPUT}"
}

@test 'shared script changes alone do not trigger a release' {
  git reset -q --hard v1.2.3
  echo '# updated' > .github/scripts/helper.sh
  git add .
  git commit -qm 'fix: adjust helper'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'sync-major=true' "${GITHUB_OUTPUT}"
}

@test 'a new reusable workflow triggers a patch release' {
  git reset -q --hard v1.2.3
  printf 'on:\n  workflow_call:\njobs: {}\n' > .github/workflows/new.yml
  git add .
  git commit -qm 'fix: add reusable workflow'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
}

@test 'removal of workflow_call triggers a release' {
  git reset -q --hard v1.2.3
  printf 'on:\n  push:\njobs: {}\n' > .github/workflows/reusable.yml
  git add .
  git commit -qm 'fix: drop reusable interface'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
}

@test 'deleting a reusable workflow triggers a release' {
  git reset -q --hard v1.2.3
  git rm -q .github/workflows/reusable.yml
  git commit -qm 'fix: remove reusable workflow'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
}

@test 'a YAML file without workflow_call does not trigger a release' {
  git reset -q --hard v1.2.3
  printf 'on:\n  push:\njobs: {}\n' > .github/workflows/other.yaml
  git add .
  git commit -qm 'ci: add push-only workflow'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'sync-major=true' "${GITHUB_OUTPUT}"
}

@test 'renaming a reusable workflow into a regular workflow triggers a release' {
  git reset -q --hard v1.2.3
  git mv .github/workflows/reusable.yml .github/workflows/ci.yml
  printf 'on:\n  push:\njobs: {}\n' > .github/workflows/ci.yml
  git add .
  git commit -qm 'fix: retire renamed reusable workflow'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
}

@test 'Actions lockfile changes do not trigger a release' {
  git reset -q --hard v1.2.3
  echo 'version: locked' > .github/workflows/actions.lock
  git add .
  git commit -qm 'ci: regenerate Actions lockfile'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'sync-major=true' "${GITHUB_OUTPUT}"
}

@test 'quoted inline workflow_call in a yaml file triggers a release' {
  git reset -q --hard v1.2.3
  printf "'on': [workflow_call]\njobs: {}\n" > .github/workflows/inline.yaml
  git add .
  git commit -qm 'fix: add quoted YAML reusable workflow'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
}

@test 'an existing local tag stops publication planning' {
  git tag v1.2.4 v1.2.3
  run bash "${PLAN_SCRIPT}"
  [ "$status" -ne 0 ]
  [[ "$output" == *'already exists locally'* ]]
}

@test 'an existing remote tag stops publication planning' {
  run env FAKE_REMOTE_TAG=refs/tags/v1.2.4 bash "${PLAN_SCRIPT}"
  [ "$status" -ne 0 ]
  [[ "$output" == *'already exists remotely'* ]]
}

@test 'manual dispatch from a non-main ref is rejected' {
  export GITHUB_REF='refs/heads/feature'
  run bash "${PLAN_SCRIPT}"
  [ "$status" -ne 0 ]
  [[ "$output" == *'refs/heads/main'* ]]
}

@test 'an advanced main is skipped without a release' {
  export FAKE_HEAD=0000000000000000000000000000000000000000
  run bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test 'GitHub API failures are not treated as missing tags' {
  export FAKE_REMOTE_ERROR=true
  run bash "${PLAN_SCRIPT}"
  [ "$status" -ne 0 ]
  [[ "$output" == *'GitHub API error'* ]]
}

@test 'publication rejects an existing remote tag' {
  run env FAKE_REMOTE_TAG=refs/tags/v1.2.4 RELEASE_TAG=v1.2.4 bash "${PUBLISH_SCRIPT}"
  [ "$status" -ne 0 ]
  [[ "$output" == *'already exists remotely'* ]]
}

@test 'publication requires every validation job to succeed' {
  workflow="${WORKFLOW_FILE}"
  for name in shell-lint markdown-lint github-actions-lint-and-scan bats-tests; do
    run grep -F "&& needs.${name}.result == 'success'" "${workflow}"
    [ "$status" -eq 0 ]
  done
}

@test 'reusable YAML trigger variants are parsed structurally' {
  local fixture
  local -a fixtures=(
    'on:\n    workflow_call:\njobs: {}\n'
    '"on":\n  "workflow_call":\njobs: {}\n'
    "'on': {'workflow_call': {}}\njobs: {}\n"
    'on: workflow_call\njobs: {}\n'
    'on: [push, workflow_call]\njobs: {}\n'
  )
  for fixture in "${fixtures[@]}"; do
    echo "fixture: ${fixture}"
    git reset -q --hard v1.2.3
    printf '%b' "${fixture}" > .github/workflows/new.yaml
    git add .
    git commit -qm 'fix: add reusable workflow'
    : > "${GITHUB_OUTPUT}"
    run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
  done
}

@test 'malformed workflow YAML fails planning even after a qualifying change' {
  printf 'on: [\n' > .github/workflows/z-invalid.yml
  git add .
  git commit -qm 'fix: invalid workflow'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test 'unrelated feature messages contribute to repository-wide severity' {
  echo documentation > README.md
  git add .
  git commit -qm 'feat: improve documentation'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'main API failures fail both planning and publication' {
  local script
  for script in "${PLAN_SCRIPT}" "${PUBLISH_SCRIPT}"; do
    echo "script: ${script}"
    run env FAKE_MAIN_ERROR=true RELEASE_TAG=v1.2.4 bash "${script}"
    [ "$status" -ne 0 ]
    [[ "$output" == *'GitHub API error'* ]]
    [ ! -s "${GITHUB_OUTPUT}" ]
    [ ! -e "${FAKE_STATE}/mutations" ]
  done
}

@test 'a partial publication retries its exact tag after validation planning' {
  run env FAKE_CREATE_ERROR=true RELEASE_TAG=v1.2.4 bash "${PUBLISH_SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
  [ -f "${FAKE_STATE}/tag" ]
  git tag v1.2.4 "${RELEASE_SHA}"

  run bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'ready=true' "${GITHUB_OUTPUT}"
  : > "${GITHUB_OUTPUT}"
  run env RELEASE_TAG=v1.2.4 bash "${PUBLISH_SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'published=true' "${GITHUB_OUTPUT}"
  [ "$(grep -c '^tag-create$' "${FAKE_STATE}/mutations")" -eq 1 ]
  [ "$(grep -c '^release-create$' "${FAKE_STATE}/mutations")" -eq 2 ]
}

@test 'retry rejects conflicting or annotated remote tag objects' {
  local script remote
  local -a remotes=(
    $'commit\t0000000000000000000000000000000000000000'
    "$(printf 'tag\t%s' "${RELEASE_SHA}")"
  )
  for script in "${PLAN_SCRIPT}" "${PUBLISH_SCRIPT}"; do
    for remote in "${remotes[@]}"; do
      echo "script: ${script}, object: ${remote}"
      run env "FAKE_REMOTE_TAG=${remote}" RELEASE_TAG=v1.2.4 bash "${script}"
      [ "$status" -ne 0 ]
      [[ "$output" == *'already exists remotely'* ]]
      [ ! -s "${GITHUB_OUTPUT}" ]
      [ ! -e "${FAKE_STATE}/mutations" ]
    done
  done
}

@test 'retry fails closed for release lookup errors or an existing release' {
  local script scenario
  local -a scenarios=(FAKE_RELEASE_ERROR=true FAKE_EXISTING_RELEASE=123)
  for script in "${PLAN_SCRIPT}" "${PUBLISH_SCRIPT}"; do
    for scenario in "${scenarios[@]}"; do
      echo "script: ${script}, scenario: ${scenario}"
      run env "${scenario}" "FAKE_REMOTE_TAG=$(printf 'commit\t%s' "${RELEASE_SHA}")" \
        RELEASE_TAG=v1.2.4 bash "${script}"
      [ "$status" -ne 0 ]
      [ ! -s "${GITHUB_OUTPUT}" ]
      [ ! -e "${FAKE_STATE}/mutations" ]
    done
  done
}

@test 'no-change runs can retry synchronization after successful publication' {
  git tag v1.2.4 "${RELEASE_SHA}"
  run env FAKE_LATEST=v1.2.4 bash "${PLAN_SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'sync-major=true' ]
  [ ! -e "${FAKE_STATE}/mutations" ]
  [ "$(yq -r '.jobs.weekly-major-version-tag.needs | join(",")' "${WORKFLOW_FILE}")" = 'plan,publish' ]
  condition="$(yq -r '.jobs.weekly-major-version-tag.if' "${WORKFLOW_FILE}")"
  [[ "${condition}" == *"!cancelled()"* ]]
  [[ "${condition}" == *"needs.plan.result == 'success'"* ]]
  [[ "${condition}" == *"needs.plan.outputs.sync-major == 'true'"* ]]
  [[ "${condition}" == *"needs.publish.outputs.published == 'true'"* ]]
}
