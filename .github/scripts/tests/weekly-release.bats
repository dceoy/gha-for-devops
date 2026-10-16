#!/usr/bin/env bats

setup() {
  export SCRIPT="${BATS_TEST_DIRNAME}/../../actions/weekly-release/weekly-release.sh"
  export TEST_DIR="${BATS_TEST_TMPDIR}/candidate"
  mkdir -p "${TEST_DIR}/.github/workflows" "${TEST_DIR}/.github/scripts"
  cd "${TEST_DIR}" || exit
  git init -q -b main
  git config user.email ci@example.invalid
  git config user.name 'Release test'
  echo 'baseline' > .github/workflows/ci.yml
  git add .
  git commit -qm 'ci: baseline'
  git tag v1.2.3
  echo 'update' >> .github/workflows/ci.yml
  git add .
  git commit -qm 'fix: update reusable workflow'

  export RELEASE_SHA
  RELEASE_SHA="$(git rev-parse HEAD)"
  export GITHUB_REPOSITORY='example/test'
  export GITHUB_REF='refs/heads/main'
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/gh" << 'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  'api repos/example/test/git/ref/heads/main')
    printf '%s\n' "${FAKE_HEAD:-${RELEASE_SHA}}"
    ;;
  'api repos/example/test/git/matching-refs/'*)
    if [[ "${FAKE_REMOTE_ERROR:-false}" == true ]]; then
      echo 'GitHub API error' >&2
      exit 1
    fi
    printf '%s\n' "${FAKE_REMOTE_TAG:-}"
    ;;
  'release list')
    printf 'v1.2.3\n'
    ;;
  *)
    echo "Unexpected gh invocation: $*" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
}

@test 'patch release is planned without requiring an earlier push CI run' {
  run bash "${SCRIPT}" plan
  [ "$status" -eq 0 ]
  grep -qx 'ready=true' "${GITHUB_OUTPUT}"
  grep -qx 'tag=v1.2.4' "${GITHUB_OUTPUT}"
}

@test 'a documentation-only commit has no release' {
  git reset -q --hard v1.2.3
  echo 'documentation' > README.md
  git add .
  git commit -qm 'docs: documentation'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${SCRIPT}" plan
  [ "$status" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test 'a feature in a squash commit body increments minor' {
  git commit --amend -qm 'fix: bundle changes' -m '* feat(workflows): add a workflow'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${SCRIPT}" plan
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'breaking changes in squash body increment minor' {
  git commit --amend -qm 'fix: bundled change' -m '* feat!: remove input'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${SCRIPT}" plan
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'BREAKING-CHANGE footer increments minor' {
  git commit --amend -qm 'fix: bundled change' -m '  BREAKING-CHANGE: removed inputs'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${SCRIPT}" plan
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'breaking fix commit increments minor instead of patch' {
  git commit --amend -qm 'fix!: change an existing workflow input'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${SCRIPT}" plan
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'BREAKING CHANGE footer increments minor' {
  git commit --amend -qm 'fix: remove old input' -m 'BREAKING CHANGE: removed old input'
  run env "RELEASE_SHA=$(git rev-parse HEAD)" bash "${SCRIPT}" plan
  [ "$status" -eq 0 ]
  grep -qx 'tag=v1.3.0' "${GITHUB_OUTPUT}"
}

@test 'an existing local tag stops publication planning' {
  git tag v1.2.4
  run bash "${SCRIPT}" plan
  [ "$status" -ne 0 ]
  [[ "$output" == *'already exists locally'* ]]
}

@test 'an existing remote tag stops publication planning' {
  run env FAKE_REMOTE_TAG=refs/tags/v1.2.4 bash "${SCRIPT}" plan
  [ "$status" -ne 0 ]
  [[ "$output" == *'already exists remotely'* ]]
}

@test 'manual dispatch from a non-main ref is rejected' {
  export GITHUB_REF='refs/heads/feature'
  run bash "${SCRIPT}" plan
  [ "$status" -ne 0 ]
  [[ "$output" == *'refs/heads/main'* ]]
}

@test 'an advanced main is skipped without a release' {
  export FAKE_HEAD=0000000000000000000000000000000000000000
  run bash "${SCRIPT}" plan
  [ "$status" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test 'GitHub API failures are not treated as missing tags' {
  export FAKE_REMOTE_ERROR=true
  run bash "${SCRIPT}" plan
  [ "$status" -ne 0 ]
  [[ "$output" == *'GitHub API error'* ]]
}

@test 'publication rejects an existing remote tag' {
  run env FAKE_REMOTE_TAG=refs/tags/v1.2.4 RELEASE_TAG=v1.2.4 bash "${SCRIPT}" publish
  [ "$status" -ne 0 ]
  [[ "$output" == *'already exists remotely'* ]]
}

@test 'publication requires every validation job to succeed' {
  workflow="${BATS_TEST_DIRNAME}/../../workflows/weekly-release.yml"
  for name in shell-lint markdown-lint github-actions-lint-and-scan bats-tests; do
    run grep -F "&& needs.${name}.result == 'success'" "${workflow}"
    [ "$status" -eq 0 ]
  done
}
