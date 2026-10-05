#!/usr/bin/env bats
#
# Regression coverage for narrow actionlint compatibility ignores. Keep the raw
# diagnostics assertions so actionlint upgrades prompt review of these ignores.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/github-actions-lint-and-scan.yml"
  RUN_SCRIPT="$(yq -r '.jobs."github-actions-lint-scan".steps[] | select(.name == "Execute actionlint") | .run' "${WORKFLOW}")"
  WORKFLOW_ACTIONLINT_VERSION="$(yq -r '.jobs."github-actions-lint-scan".env.ACTIONLINT_VERSION' "${WORKFLOW}")"
  MISE_ACTIONLINT_VERSION="$(yq -r '.tools.actionlint' "${REPO_ROOT}/mise.toml")"
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

  cat > .github/workflows/job-context.yml << 'EOF'
name: Reusable workflow metadata
on:
  workflow_call:
jobs:
  metadata:
    runs-on: ubuntu-latest
    steps:
      - name: Read reusable workflow metadata
        env:
          WORKFLOW_REPOSITORY: ${{ job.workflow_repository }}
          WORKFLOW_SHA: ${{ job.workflow_sha }}
        run: |
          printf '%s\n' "${WORKFLOW_REPOSITORY}"
          printf '%s\n' "${WORKFLOW_SHA}"
EOF

  cat > .github/workflows/invalid-runner-context.yml << 'EOF'
name: Invalid runner metadata
on:
  workflow_call:
jobs:
  metadata:
    runs-on: ubuntu-latest
    steps:
      - name: Use invalid runner metadata
        env:
          RUNNER_WORKFLOW_REPOSITORY: ${{ runner.workflow_repository }}
          RUNNER_WORKFLOW_SHA: ${{ runner.workflow_sha }}
        run: |
          printf '%s\\n' "${RUNNER_WORKFLOW_REPOSITORY}"
          printf '%s\\n' "${RUNNER_WORKFLOW_SHA}"
EOF

  git add .github/workflows/self-reference.yml .github/workflows/job-context.yml .github/workflows/invalid-runner-context.yml
}

teardown() {
  cd /
  rm -rf "${TEST_REPO}"
}

run_actionlint_step() {
  local compatibility_mode="$1"
  local server_url="$2"

  run env \
    ACTIONLINT_COMPATIBILITY_MODE="${compatibility_mode}" \
    ACTIONLINT_EXTRA_IGNORE_REGEX="" \
    GITHUB_SERVER_URL="${server_url}" \
    SEARCH_PATH=".github/workflows" \
    bash -euo pipefail -c "${RUN_SCRIPT}"
}

@test "mise and reusable workflow use the same actionlint version" {
  [ "${MISE_ACTIONLINT_VERSION#v}" = "${WORKFLOW_ACTIONLINT_VERSION#v}" ]

  run actionlint -version

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${WORKFLOW_ACTIONLINT_VERSION#v}"* ]]
}

@test "raw mode reports the known false positives" {
  run_actionlint_step false https://github.com

  [ "${status}" -eq 1 ]
  [[ "${output}" == *'specifying action "$/.github/actions/example" in invalid format because ref is missing'* ]]
  [[ "${output}" == *'reusable workflow call "$/.github/workflows/reusable.yml" at "uses" is not following the format'* ]]
  [[ "${output}" == *'property "workflow_repository" is not defined in object type'* ]]
  [[ "${output}" == *'property "workflow_sha" is not defined in object type'* ]]
  [[ "${output}" == *'${{ job.workflow_repository }}'* ]]
  [[ "${output}" == *'${{ job.workflow_sha }}'* ]]
  [[ "${output}" == *'${{ runner.workflow_repository }}'* ]]
  [[ "${output}" == *'${{ runner.workflow_sha }}'* ]]
}

@test "compatibility mode suppresses only the known false positives on GitHub.com" {
  run_actionlint_step true https://github.com

  [ "${status}" -eq 1 ]
  [[ "${output}" == *'${{ runner.workflow_repository }}'* ]]
  [[ "${output}" == *'${{ runner.workflow_sha }}'* ]]
  [[ "${output}" != *'${{ job.workflow_repository }}'* ]]
  [[ "${output}" != *'${{ job.workflow_sha }}'* ]]
}

@test "compatibility mode leaves raw diagnostics on GitHub Enterprise Server" {
  run_actionlint_step true https://github.example.com

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"actionlint compatibility ignores are disabled outside GitHub.com"* ]]
  [[ "${output}" == *'specifying action "$/.github/actions/example" in invalid format because ref is missing'* ]]
  [[ "${output}" == *'reusable workflow call "$/.github/workflows/reusable.yml" at "uses" is not following the format'* ]]
  [[ "${output}" == *'property "workflow_repository" is not defined in object type'* ]]
  [[ "${output}" == *'property "workflow_sha" is not defined in object type'* ]]
  [[ "${output}" == *'${{ job.workflow_repository }}'* ]]
  [[ "${output}" == *'${{ job.workflow_sha }}'* ]]
  [[ "${output}" == *'${{ runner.workflow_repository }}'* ]]
  [[ "${output}" == *'${{ runner.workflow_sha }}'* ]]
}
