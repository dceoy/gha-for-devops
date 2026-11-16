#!/usr/bin/env bats

setup() {
  export PREPARE_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/python-package-release-on-pypi-and-github.yml"
  export PLAN_SCRIPT="${BATS_TEST_TMPDIR}/plan.sh"
  export ASSETS_SCRIPT="${BATS_TEST_TMPDIR}/assets.sh"
  export VERIFY_SCRIPT="${BATS_TEST_TMPDIR}/verify.sh"
  yq -r '.jobs."prepare-plan".steps[] | select(.id == "plan") | .run' "${PREPARE_WORKFLOW}" > "${PLAN_SCRIPT}"
  yq -r '.jobs."prepare-verify-source".steps[] | select(.id == "verify") | .run' "${PREPARE_WORKFLOW}" > "${VERIFY_SCRIPT}"
  yq -r '.jobs."prepare-attach-assets".steps[] | select(.name == "Check distribution names and version") | .run' "${PREPARE_WORKFLOW}" > "${ASSETS_SCRIPT}"
}

make_fixture() {
  local root="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${root}/pkg" "${root}/bin"
  cd "${root}" || exit 1
  git init -q -b main
  git config user.email ci@example.invalid
  git config user.name 'Release tests'
  cat > pkg/pyproject.toml << 'TOML'
[project]
name = "foo-bar"
version = "1.2.3"
TOML
  git add .
  git commit -qm 'test: initial release'
  cat > bin/gh << 'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  'api repos/example/test/git/ref/heads/main')
    printf '%s\n' "${MOCK_BRANCH_SHA:-${SOURCE_SHA}}"
    ;;
  'run list')
    printf '%s\n' "${MOCK_CI_RUNS:-1}"
    ;;
  'release list')
    printf '%s\n' "${MOCK_LATEST:-v1.2.2}"
    ;;
  'release view')
    exit 1
    ;;
  'api repos/example/test/git/matching-refs/tags/v1.2.3')
    [ -z "${MOCK_TAG_TYPE:-}" ] || printf '%s\t%s\n' "${MOCK_TAG_TYPE}" "${MOCK_TAG_SHA}"
    ;;
  'api repos/example/test/git/tags/'*)
    printf 'commit\t%s\n' "${MOCK_TAG_TARGET}"
    ;;
  *)
    echo "Unexpected gh command: $*" >&2
    exit 3
    ;;
esac
MOCK
  chmod +x bin/gh
  export PATH="${root}/bin:${PATH}"
  export PACKAGE_PATH=pkg
  export RELEASE_BRANCH=main
  export CI_WORKFLOW=ci.yml
  export GITHUB_REPOSITORY=example/test
  export RELEASE_TAG=v1.2.3
  export GH_TOKEN=test
  export SOURCE_SHA
  SOURCE_SHA="$(git rev-parse HEAD)"
  export GITHUB_SHA="${SOURCE_SHA}"
  export GITHUB_OUTPUT="${root}/outputs"
  : > "${GITHUB_OUTPUT}"
}

@test 'unified workflow exposes prepare outputs and legacy default' {
  [ "$(yq -r '.on.workflow_call.inputs.mode.default' "${PREPARE_WORKFLOW}")" = legacy ]
  [[ "$(yq -r '.on.workflow_call.outputs."release-tag".value' "${PREPARE_WORKFLOW}")" == *'jobs.prepare-draft-release.outputs.release-tag'* ]]
  [[ "$(yq -r '.jobs."python-release-build".if' "${PREPARE_WORKFLOW}")" == *"inputs.mode == 'prepare'"* ]]
  [ "$(yq -r '.jobs."prepare-draft-release".with.draft' "${PREPARE_WORKFLOW}")" = true ]
  [ "$(yq -r '.jobs."prepare-draft-release".with."source-branch"' "${PREPARE_WORKFLOW}")" = "${{ inputs.release-branch }}" ]
  [ "$(yq -r '.jobs."prepare-attach-assets".permissions."id-token"' "${PREPARE_WORKFLOW}")" = write ]
  [ "$(yq -r '.jobs."prepare-plan".permissions.actions' "${PREPARE_WORKFLOW}")" = read ]
  [[ "$(yq -r '.jobs."python-release-pypi".if' "${PREPARE_WORKFLOW}")" == *"inputs.mode == 'legacy'"* ]]
}

@test 'release plan accepts only a successful push CI and increasing pyproject version' {
  make_fixture
  run bash -euo pipefail "${PLAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -qx 'tag=v1.2.3' "${GITHUB_OUTPUT}"
  grep -qx "source-sha=${SOURCE_SHA}" "${GITHUB_OUTPUT}"
}

@test 'release plan rejects missing CI and non-increasing versions' {
  make_fixture
  run env MOCK_CI_RUNS=0 bash -euo pipefail "${PLAN_SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'No successful ci.yml push run'* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]

  run env MOCK_LATEST=v1.2.3 bash -euo pipefail "${PLAN_SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'must exceed the latest release'* ]]
}

@test 'release plan skips when main advanced' {
  make_fixture
  run env MOCK_BRANCH_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb bash -euo pipefail "${PLAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
  [[ "${output}" == *'advanced since validation'* ]]
}

@test 'distribution validator matches normalized Python package name and release' {
  local root="${BATS_TEST_TMPDIR}/dist-check"
  mkdir -p "${root}/dist"
  cd "${root}" || exit 1
  touch dist/foo_bar-1.2.3.tar.gz dist/foo_bar-1.2.3-py3-none-any.whl
  run env PROJECT_NAME=foo-bar RELEASE_TAG=v1.2.3 bash -euo pipefail "${ASSETS_SCRIPT}"
  [ "${status}" -eq 0 ]
  run env PROJECT_NAME=foo-bar RELEASE_TAG=v1.2.4 bash -euo pipefail "${ASSETS_SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Missing source distribution'* ]]
}

@test 'source verifier accepts missing, lightweight and annotated tags for the validated source' {
  make_fixture
  run bash -euo pipefail "${VERIFY_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -qx 'current=true' "${GITHUB_OUTPUT}"

  : > "${GITHUB_OUTPUT}"
  run env MOCK_TAG_TYPE=commit MOCK_TAG_SHA="${SOURCE_SHA}" bash -euo pipefail "${VERIFY_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -qx 'current=true' "${GITHUB_OUTPUT}"

  : > "${GITHUB_OUTPUT}"
  run env MOCK_TAG_TYPE=tag MOCK_TAG_SHA=cccccccccccccccccccccccccccccccccccccccc MOCK_TAG_TARGET="${SOURCE_SHA}" bash -euo pipefail "${VERIFY_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -qx 'current=true' "${GITHUB_OUTPUT}"
}

@test 'source verifier rejects an existing tag that resolves to another commit' {
  make_fixture
  run env MOCK_TAG_TYPE=commit MOCK_TAG_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb bash -euo pipefail "${VERIFY_SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'does not resolve to the validated source'* ]]

  run env MOCK_TAG_TYPE=tag MOCK_TAG_SHA=cccccccccccccccccccccccccccccccccccccccc MOCK_TAG_TARGET=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb bash -euo pipefail "${VERIFY_SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'does not resolve to the validated source'* ]]
}
