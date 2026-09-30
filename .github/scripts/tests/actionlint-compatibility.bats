#!/usr/bin/env bats
#
# Regression coverage for actionlint compatibility handling of GitHub.com's
# $/ self-repository syntax. The raw-mode assertion should start failing once
# the pinned actionlint version gains native support, prompting workaround
# removal.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/github-actions-lint-and-scan.yml"
  RUN_SCRIPT="$(yq -r '.jobs."github-actions-lint-scan".steps[] | select(.name == "Execute actionlint") | .run' "${WORKFLOW}")"
  TEST_REPO="$(mktemp -d)"

  cd "${TEST_REPO}" || exit
  git init -q
  mkdir -p .github/workflows

  cat > .github/workflows/self-reference.yml << 'EOF'
name: Self reference
on:
  push:
jobs:
  action:
    runs-on: ubuntu-latest
    steps:
      - uses: $/.github/actions/example
  reusable:
    uses: $/.github/workflows/reusable.yml
EOF

  git add .github/workflows/self-reference.yml
}

teardown() {
  cd /
  rm -rf "${TEST_REPO}"
}

run_actionlint_step() {
  env \
    ACTIONLINT_COMPATIBILITY_MODE="$1" \
    ACTIONLINT_EXTRA_IGNORE_REGEX="" \
    GITHUB_SERVER_URL="$2" \
    SEARCH_PATH=".github/workflows" \
    bash -c "${RUN_SCRIPT}"
}

@test "raw actionlint rejects unsupported self-repository syntax" {
  run run_actionlint_step false https://github.com

  [ "${status}" -ne 0 ]
  [[ "${output}" == *'specifying action "$/.github/actions/example" in invalid format because ref is missing'* ]]
  [[ "${output}" == *'reusable workflow call "$/.github/workflows/reusable.yml" at "uses" is not following the format'* ]]
}

@test "compatibility mode suppresses the known diagnostics on GitHub.com" {
  run run_actionlint_step true https://github.com

  [ "${status}" -eq 0 ]
}

@test "compatibility mode does not suppress diagnostics on GitHub Enterprise Server" {
  run run_actionlint_step true https://github.example.com

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"actionlint compatibility ignores are disabled outside GitHub.com"* ]]
}
