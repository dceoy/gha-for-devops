#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/go-package-test.yml"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures/go-package-test"
  TEST_TEMP="$(mktemp -d)"
}

teardown() {
  rm -rf "${TEST_TEMP}"
}

prepare_fixture() {
  local fixture_name="$1"
  local destination="$2"

  mkdir -p "${destination}"
  while IFS= read -r -d '' fixture; do
    relative_path="${fixture#"${FIXTURES}/${fixture_name}/"}"
    output_path="${destination}/${relative_path%.fixture}"
    mkdir -p "$(dirname "${output_path}")"
    cp "${fixture}" "${output_path}"
  done < <(find "${FIXTURES}/${fixture_name}" -type f -name '*.fixture' -print0)
  go -C "${destination}" mod init "example.com/${fixture_name}"
}

extract_step() {
  local step_name="$1"
  local output_script="$2"

  yq -r ".jobs.\"go-package-test\".steps[] | select(.name == \"${step_name}\") | .run" "${WORKFLOW}" > "${output_script}"
}

run_step() {
  local step_name="$1"
  local working_directory="$2"
  shift 2
  local step_script="${TEST_TEMP}/${step_name// /-}.sh"

  extract_step "${step_name}" "${step_script}"
  # shellcheck disable=SC2016
  run env "$@" bash -c 'cd "$1" && exec bash -euo pipefail "$2"' _ "${working_directory}" "${step_script}"
}

@test "workflow scripts pass for a valid Go project" {
  project="${TEST_TEMP}/success"
  prepare_fixture success "${project}"

  run_step "Verify formatting" "${project}"
  [ "${status}" -eq 0 ]

  run_step "Run go vet" "${project}" GO_TEST_PACKAGE_PATTERN=./...
  [ "${status}" -eq 0 ]

  run_step "Run tests" "${project}" \
    GO_TEST_PACKAGE_PATTERN=./... \
    GO_TEST_RACE=false \
    GO_TEST_COVERAGE=false \
    GO_COVERAGE_PROFILE=coverage.out
  [ "${status}" -eq 0 ]

  run_step "Verify build" "${project}" GO_BUILD_PACKAGE_PATTERN=./...
  [ "${status}" -eq 0 ]
}

@test "formatting failures fail the formatting step" {
  project="${TEST_TEMP}/format-failure"
  prepare_fixture format-failure "${project}"

  run_step "Verify formatting" "${project}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not formatted"* ]]
}

@test "test failures fail the test step" {
  project="${TEST_TEMP}/test-failure"
  prepare_fixture test-failure "${project}"

  run_step "Run tests" "${project}" \
    GO_TEST_PACKAGE_PATTERN=./... \
    GO_TEST_RACE=false \
    GO_TEST_COVERAGE=false \
    GO_COVERAGE_PROFILE=coverage.out

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL"* ]]
}

@test "race and coverage arguments are constructed without shell splitting" {
  project="${TEST_TEMP}/argument-construction"
  fake_bin="${TEST_TEMP}/fake-bin"
  args_file="${TEST_TEMP}/go-args"
  mkdir -p "${project}" "${fake_bin}"
  cat > "${fake_bin}/go" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${GO_ARGS_FILE}"
EOF
  chmod +x "${fake_bin}/go"

  run_step "Run tests" "${project}" \
    PATH="${fake_bin}:${PATH}" \
    GO_ARGS_FILE="${args_file}" \
    GO_TEST_PACKAGE_PATTERN=./... \
    GO_TEST_RACE=true \
    GO_TEST_COVERAGE=true \
    GO_COVERAGE_PROFILE=reports/coverage.out

  [ "${status}" -eq 0 ]
  [ "$(paste -sd ' ' "${args_file}")" = "test -race -coverprofile=reports/coverage.out -covermode=atomic ./..." ]
  [ -d "${project}/reports" ]
}

@test "workflow scripts support a nested working directory" {
  repository="${TEST_TEMP}/repository"
  project="${repository}/services/example"
  prepare_fixture success "${project}"

  run_step "Validate inputs" "${repository}" \
    GO_WORKING_DIRECTORY=services/example \
    GO_TEST_PACKAGE_PATTERN=./... \
    GO_BUILD_PACKAGE_PATTERN=./... \
    GO_COVERAGE_PROFILE=reports/coverage.out \
    GO_COVERAGE_ARTIFACT_NAME=go-coverage \
    GO_COVERAGE_RETENTION_DAYS=7
  [ "${status}" -eq 0 ]

  run_step "Verify formatting" "${project}"
  [ "${status}" -eq 0 ]

  run_step "Run go vet" "${project}" GO_TEST_PACKAGE_PATTERN=./...
  [ "${status}" -eq 0 ]

  run_step "Run tests" "${project}" \
    GO_TEST_PACKAGE_PATTERN=./... \
    GO_TEST_RACE=false \
    GO_TEST_COVERAGE=true \
    GO_COVERAGE_PROFILE=reports/coverage.out
  [ "${status}" -eq 0 ]
  [ -f "${project}/reports/coverage.out" ]
}

@test "default package patterns cover every module in a Go workspace" {
  workspace="${TEST_TEMP}/workspace"
  module_a="${workspace}/module-a"
  module_b="${workspace}/module-b"
  prepare_fixture success "${module_a}"
  prepare_fixture success "${module_b}"
  go -C "${module_a}" mod edit -module=example.com/module-a
  go -C "${module_b}" mod edit -module=example.com/module-b
  go -C "${workspace}" work init ./module-a ./module-b

  run_step "Run go vet" "${workspace}" GO_TEST_PACKAGE_PATTERN=./...
  [ "${status}" -eq 0 ]

  run_step "Run tests" "${workspace}" \
    GO_TEST_PACKAGE_PATTERN=./... \
    GO_TEST_RACE=false \
    GO_TEST_COVERAGE=false \
    GO_COVERAGE_PROFILE=coverage.out
  [ "${status}" -eq 0 ]

  run_step "Verify build" "${workspace}" GO_BUILD_PACKAGE_PATTERN=./...
  [ "${status}" -eq 0 ]
}

@test "go workspace cache configuration covers nested module lockfiles" {
  workspace="${TEST_TEMP}/workspace"
  module_a="${workspace}/module-a"
  module_b="${workspace}/module-b"
  prepare_fixture success "${module_a}"
  prepare_fixture success "${module_b}"
  go -C "${module_a}" mod edit -module=example.com/module-a
  go -C "${module_b}" mod edit -module=example.com/module-b
  go -C "${workspace}" work init ./module-a ./module-b
  : > "${module_a}/go.sum"
  : > "${module_b}/go.sum"

  mapfile -t patterns < <(
    yq -r '.jobs."go-package-test".steps[] | select(.name == "Set up Go") | .with."cache-dependency-path"' "${WORKFLOW}" \
      | sed "s#\${{ inputs.working-directory }}#${workspace}#g"
  )

  shopt -s globstar nullglob
  matches=()
  for pattern in "${patterns[@]}"; do
    for match in ${pattern}; do
      matches+=("${match}")
    done
  done
  shopt -u globstar nullglob

  [[ " ${matches[*]} " == *" ${module_a}/go.sum "* ]]
  [[ " ${matches[*]} " == *" ${module_b}/go.sum "* ]]
}

@test "Go module and build caches also cover projects without go.sum" {
  fallback="$(yq -o json '.jobs."go-package-test".steps[] | select(.name == "Cache Go projects without checksum files")' "${WORKFLOW}")"
  [ "$(jq -r '.uses' <<< "${fallback}")" = 'actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9' ]
  [[ "$(jq -r '.if' <<< "${fallback}")" == *'go.work.sum'* ]]
  [[ "$(jq -r '.with.path' <<< "${fallback}")" == *'~/.cache/go-build'* ]]
  [[ "$(jq -r '.with.key' <<< "${fallback}")" == *'steps.setup-go.outputs.go-version'* ]]
}

@test "Go lint caches pinned scanner versions and invokes Go-installed binaries" {
  local workflow
  workflow="${REPO_ROOT}/.github/workflows/go-package-lint-and-scan.yml"
  for tool in GOLANGCI_LINT_VERSION GOSEC_VERSION GOVULNCHECK_VERSION; do
    [[ "$(yq -r ".jobs.\"go-package-lint-and-scan\".env.${tool}" "${workflow}")" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
    grep -Fq "env.${tool}" "${workflow}"
  done
  [ "$(yq -r '.jobs."go-package-lint-and-scan".steps[] | select(.name == "Cache Go tools") | .with.key' "${workflow}" | grep -o 'go-tools-v3-' | wc -l)" -eq 1 ]
  for tool in golangci-lint gosec govulncheck; do
    grep -Fq "\$(go env GOPATH)/bin/${tool}" "${workflow}"
  done
  run ! grep -Eq 'go install .*@latest' "${workflow}"
}

@test "coverage artifacts can be named uniquely per workflow invocation" {
  run yq -r '.on.workflow_call.inputs."coverage-artifact-name".default' "${WORKFLOW}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "go-coverage" ]

  run yq -r '.jobs."go-package-test".steps[] | select(.name == "Upload coverage profile") | .with.name' "${WORKFLOW}"
  [ "${status}" -eq 0 ]
  # shellcheck disable=SC2016
  [ "${output}" = '${{ inputs.coverage-artifact-name }}' ]
}

@test "flag-like and parent-directory package patterns are rejected" {
  repository="${TEST_TEMP}/repository"
  prepare_fixture success "${repository}"

  run_step "Validate inputs" "${repository}" \
    GO_WORKING_DIRECTORY=. \
    GO_TEST_PACKAGE_PATTERN=-x \
    GO_BUILD_PACKAGE_PATTERN=../... \
    GO_COVERAGE_PROFILE=coverage.out \
    GO_COVERAGE_ARTIFACT_NAME=go-coverage \
    GO_COVERAGE_RETENTION_DAYS=7

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"test-package-pattern"* ]]
}

@test "unsafe coverage artifact names are rejected" {
  repository="${TEST_TEMP}/repository"
  prepare_fixture success "${repository}"

  run_step "Validate inputs" "${repository}" \
    GO_WORKING_DIRECTORY=. \
    GO_TEST_PACKAGE_PATTERN=./... \
    GO_BUILD_PACKAGE_PATTERN=./... \
    GO_COVERAGE_PROFILE=coverage.out \
    'GO_COVERAGE_ARTIFACT_NAME=coverage/name' \
    GO_COVERAGE_RETENTION_DAYS=7

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"coverage-artifact-name"* ]]
}
