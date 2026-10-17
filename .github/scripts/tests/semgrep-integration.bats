#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOWS=(
    python-package-lint-and-scan.yml
    typescript-package-lint-and-scan.yml
    go-package-lint-and-scan.yml
    shell-lint.yml
    github-actions-lint-and-scan.yml
    terraform-lint-and-scan.yml
    docker-lint-and-scan.yml
    html-lint-and-scan.yml
  )
}

@test "Supported lint and scan workflows expose optional Semgrep and enforce findings" {
  for workflow in "${WORKFLOWS[@]}"; do
    file="${REPO_ROOT}/.github/workflows/${workflow}"
    [[ "$(yq -r '.on.workflow_call.inputs."use-semgrep".default' "${file}")" == true ]]
    grep -Fq 'if: inputs.use-semgrep' "${file}"
    grep -Fq "uvx semgrep@latest scan \\" "${file}"
    grep -Fq -- '--config p/default --metrics off --error' "${file}"
  done
}

@test "Local QA runs one uvx-managed Semgrep scan with no cloud credentials" {
  file="${REPO_ROOT}/.agents/skills/local-qa/scripts/qa.sh"
  [[ "$(grep -c 'uvx semgrep@latest scan --config p/default' "${file}")" -eq 1 ]]
  grep -Fq "uvx semgrep@latest scan" "${file}"
  bash -n "${file}"
}

# Run the actual workflow scripts with a recording CLI so target selection can be
# checked without downloading Semgrep or fetching registry rules.
prepare_consumer() {
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/consumer/nested"
  CONSUMER="${BATS_TEST_TMPDIR}/consumer"
  export SEMGREP_ARGS="${BATS_TEST_TMPDIR}/semgrep-args"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  cat > "${BATS_TEST_TMPDIR}/bin/uvx" << 'SH'
#!/usr/bin/env bash
printf '%s\0' "$@" > "${SEMGREP_ARGS}"
exit "${SEMGREP_EXIT_CODE:-0}"
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/uvx"
  git -C "${CONSUMER}" init --quiet
  touch "${CONSUMER}/nested/selected file.sh" "${CONSUMER}/nested/unrelated.sh"
  git -C "${CONSUMER}" add .
}

run_semgrep_step() {
  local workflow="$1"
  local directory="$2"
  shift 2
  local script="${BATS_TEST_TMPDIR}/semgrep-step.sh"
  yq -r '.jobs[].steps[] | select(.name == "Run Semgrep SAST scan") | .run' \
    "${REPO_ROOT}/.github/workflows/${workflow}" > "${script}"
  # shellcheck disable=SC2016
  run env "$@" bash -c 'cd "$1" && exec bash -euo pipefail "$2"' _ "${directory}" "${script}"
}

@test "Semgrep steps execute for consumers of all eight workflows and propagate findings" {
  prepare_consumer
  for workflow in "${WORKFLOWS[@]}"; do
    run_semgrep_step "${workflow}" "${CONSUMER}" FILE_NAMES='*.sh' SCAN_TARGET=.
    [ "${status}" -eq 0 ]
    mapfile -d '' -t args < "${SEMGREP_ARGS}"
    [ "${args[0]}" = semgrep@latest ]
    [ "${args[1]}" = scan ]
    [[ " ${args[*]} " == *' --config p/default --metrics off --error '* ]]

    run_semgrep_step "${workflow}" "${CONSUMER}" FILE_NAMES='*.sh' SCAN_TARGET=. SEMGREP_EXIT_CODE=1
    [ "${status}" -eq 1 ]
  done
}

@test "Docker Semgrep accepts single-file and directory scan targets with spaces" {
  prepare_consumer
  workflow=docker-lint-and-scan.yml
  file="${REPO_ROOT}/.github/workflows/${workflow}"
  [ "$(yq -r '.jobs[].steps[] | select(.name == "Run Semgrep SAST scan") | .working-directory' "${file}")" = . ]
  # shellcheck disable=SC2016
  [ "$(yq -r '.jobs[].steps[] | select(.name == "Run Semgrep SAST scan") | .env.SCAN_TARGET' "${file}")" = '${{ inputs.trivy-scan-ref }}' ]
  mkdir -p "${CONSUMER}/docker files"
  touch "${CONSUMER}/docker files/Dockerfile"
  for target in 'docker files/Dockerfile' 'docker files'; do
    run_semgrep_step "${workflow}" "${CONSUMER}" "SCAN_TARGET=${target}"
    [ "${status}" -eq 0 ]
    mapfile -d '' -t args < "${SEMGREP_ARGS}"
    [ "${args[-2]}" = -- ]
    [ "${args[-1]}" = "${target}" ]
  done
}

@test "Shell Semgrep honors restricted file-names relative to search-path" {
  prepare_consumer
  run_semgrep_step shell-lint.yml "${CONSUMER}/nested" 'FILE_NAMES=selected file.sh'
  [ "${status}" -eq 0 ]
  mapfile -d '' -t args < "${SEMGREP_ARGS}"
  [ "${args[-2]}" = -- ]
  [ "${args[-1]}" = 'selected file.sh' ]
  [[ " ${args[*]} " != *unrelated.sh* ]]
}

@test "Shell Semgrep skips unmatched selections and rejects empty file-names" {
  prepare_consumer
  run_semgrep_step shell-lint.yml "${CONSUMER}" FILE_NAMES=missing.sh
  [ "${status}" -eq 0 ]
  [ ! -e "${SEMGREP_ARGS}" ]
  run_semgrep_step shell-lint.yml "${CONSUMER}" FILE_NAMES=
  [ "${status}" -eq 1 ]
  [ ! -e "${SEMGREP_ARGS}" ]
}

@test "Semgrep uses uvx latest and automatic setup-uv caching" {
  run ! grep -q semgrep "${REPO_ROOT}/mise.toml"
  for workflow in "${WORKFLOWS[@]}"; do
    file="${REPO_ROOT}/.github/workflows/${workflow}"
    grep -Fq 'uvx semgrep@latest scan' "${file}"
    run ! grep -q SEMGREP_VERSION "${file}"
    if [[ "${workflow}" != python-package-lint-and-scan.yml ]]; then
      [ "$(yq -r '.jobs[].steps[] | select(.name == "Set up uv for Semgrep") | .with."enable-cache"' "${file}")" = auto ]
    fi
  done
}
