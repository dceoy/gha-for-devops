#!/usr/bin/env bats

setup() {
  export RELEASE_FINALIZE_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/python-package-release-on-pypi-and-github.yml"
}

@test 'Python release finalization is a callable, least-privilege workflow' {
  [ "$(yq -r '.on.workflow_call.inputs."release-tag".required' "${RELEASE_FINALIZE_WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs."release-branch".default' "${RELEASE_FINALIZE_WORKFLOW}")" = main ]
  [ "$(yq -r '.permissions | length' "${RELEASE_FINALIZE_WORKFLOW}")" = 0 ]
  [ "$(yq -r '.jobs."release-finalize".permissions.contents' "${RELEASE_FINALIZE_WORKFLOW}")" = write ]
  [[ "$(yq -r '.jobs."release-finalize".if' "${RELEASE_FINALIZE_WORKFLOW}")" == *"inputs.mode == 'finalize'"* ]]
  [ "$(yq -r '.on.workflow_call.inputs.mode.default' "${RELEASE_FINALIZE_WORKFLOW}")" = tag-release ]
}

run_finalize() {
  local script="${BATS_TEST_TMPDIR}/finalize.sh"
  local mock_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${mock_bin}"
  yq -r '.jobs."release-finalize".steps[0].run' "${RELEASE_FINALIZE_WORKFLOW}" > "${script}"
  cat > "${mock_bin}/gh" << 'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_CALLS}"
case "$1 $2" in
  'api repos/example/pkg/git/ref/heads/main')
    echo "${MOCK_BRANCH_SHA:-0123456789abcdef0123456789abcdef01234567}"
    ;;
  'api repos/example/pkg/commits/v1.2.3')
    echo "${MOCK_TAG_SHA:-0123456789abcdef0123456789abcdef01234567}"
    ;;
  'release view')
    printf '{"isDraft":%s,"assets":[{"name":"%s"},{"name":"%s"}]}\n' \
      "${MOCK_DRAFT:-true}" "${MOCK_WHEEL:-pkg-1.2.3-py3-none-any.whl}" \
      "${MOCK_SDIST:-pkg-1.2.3.tar.gz}"
    ;;
  'release edit') ;;
  *)
    echo "Unexpected gh command: $*" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "${mock_bin}/gh"
  export GH_CALLS="${BATS_TEST_TMPDIR}/gh-calls"
  : > "${GH_CALLS}"
  local original_path="${PATH}"
  run env PATH="${mock_bin}:${original_path}" \
    GITHUB_REF=refs/heads/main GITHUB_REPOSITORY=example/pkg \
    RELEASE_TAG=v1.2.3 RELEASE_BRANCH=main \
    SOURCE_SHA=0123456789abcdef0123456789abcdef01234567 PROJECT_NAME=pkg "$@" \
    bash -euo pipefail "${script}"
}

@test 'publishes a current draft with wheel and sdist after validating tag and branch' {
  run_finalize
  [ "${status}" -eq 0 ]
  grep -Fxq 'release edit v1.2.3 --repo example/pkg --draft=false' "${GH_CALLS}"
}

@test 'refuses publication when the source branch advanced' {
  run_finalize MOCK_BRANCH_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Release branch advanced'* ]]
  run ! grep -q 'release edit' "${GH_CALLS}"
}

@test 'refuses publication when the release tag resolves to another commit' {
  run_finalize MOCK_TAG_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'does not resolve'* ]]
  run ! grep -q 'release edit' "${GH_CALLS}"
}

@test 'refuses publication when the draft is already published' {
  run_finalize MOCK_DRAFT=false
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'must be a draft'* ]]
  run ! grep -q 'release edit' "${GH_CALLS}"
}

@test 'refuses publication when the draft is missing a wheel' {
  run_finalize MOCK_WHEEL=missing.txt
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'wheel and source distribution'* ]]
  run ! grep -q 'release edit' "${GH_CALLS}"
}

@test 'refuses publication from an unexpected ref' {
  run_finalize GITHUB_REF=refs/heads/topic
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Release must run on main'* ]]
  run ! grep -q 'release edit' "${GH_CALLS}"
}
@test 'refuses publication when the draft is missing an sdist' {
  run_finalize MOCK_SDIST=missing.txt
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'matching wheel and source distribution'* ]]
  run ! grep -q 'release edit' "${GH_CALLS}"
}

@test 'refuses stale distribution versions even when both extensions exist' {
  run_finalize MOCK_WHEEL=pkg-1.2.2-py3-none-any.whl MOCK_SDIST=pkg-1.2.2.tar.gz
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'matching wheel and source distribution'* ]]
  run ! grep -q 'release edit' "${GH_CALLS}"
}

@test 'refuses an invalid project name' {
  run_finalize PROJECT_NAME=../other
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Invalid project-name'* ]]
  run ! grep -q 'release edit' "${GH_CALLS}"
}

@test 'github-only mode finalizes only after draft and signed asset attachment succeed' {
  [ "$(yq -r '.on.workflow_call.inputs.mode.default' "${RELEASE_FINALIZE_WORKFLOW}")" = tag-release ]
  local workflow="${RELEASE_FINALIZE_WORKFLOW}"
  local finalize_if
  finalize_if="$(yq -r '.jobs."release-finalize".if' "${workflow}")"
  [[ "${finalize_if}" == *"inputs.mode == 'github-only'"* ]]
  [[ "${finalize_if}" == *"needs.prepare-draft-release.result == 'success'"* ]]
  [[ "${finalize_if}" == *"needs.prepare-attach-assets.result == 'success'"* ]]
  [[ "${finalize_if}" == *"needs.python-release-build.result == 'success'"* ]]
  [[ "${finalize_if}" == *"!cancelled()"* ]]
  [ "$(yq -r '.jobs."release-finalize".needs | contains(["validate", "prepare-draft-release", "prepare-attach-assets", "python-release-build"])' "${workflow}")" = true ]
  [[ "$(yq -r '.jobs."release-finalize".steps[0].env.RELEASE_TAG' "${workflow}")" == *"needs.prepare-draft-release.outputs.release-tag"* ]]
  [[ "$(yq -r '.jobs."release-finalize".steps[0].env.PROJECT_NAME' "${workflow}")" == *"needs.python-release-build.outputs.project-name"* ]]
  [[ "$(yq -r '.jobs."python-release-pypi".if' "${workflow}")" == *"inputs.mode == 'tag-release'"* ]]
  [[ "$(yq -r '.jobs."python-release-testpypi".if' "${workflow}")" == *"inputs.mode == 'tag-release'"* ]]
}
