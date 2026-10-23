#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  SCAN_WORKFLOW="${REPO_ROOT}/.github/workflows/source-security-scan.yml"
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
  local directory="$1"
  shift
  local script="${BATS_TEST_TMPDIR}/semgrep-step.sh"
  yq -r '.jobs."source-security-scan".steps[] | select(.name == "Run Semgrep SAST scan") | .run' "${SCAN_WORKFLOW}" > "${script}"
  # shellcheck disable=SC2016
  run env "SEMGREP_INCLUDES=*.sh" "SEMGREP_TARGET=." "SEMGREP_FILE_NAMES=" \
    "SEMGREP_RESTRICT_TO_FILES=false" "$@" \
    bash -c 'cd "$1" && exec bash -euo pipefail "$2"' _ "${directory}" "${script}"
}

@test "All eight linters delegate Semgrep to the shared source security workflow" {
  for workflow in "${WORKFLOWS[@]}"; do
    local path="${REPO_ROOT}/.github/workflows/${workflow}"
    [ "$(yq -r '.on.workflow_call.inputs."use-semgrep".default' "${path}")" = true ]
    [ "$(yq -r '.jobs.* | select(.uses == "$/.github/workflows/source-security-scan.yml").uses' "${path}")" = '$/.github/workflows/source-security-scan.yml' ]
    [ "$(yq -r '.on.workflow_call.inputs."security-runs-on".default' "${path}")" = ubuntu-slim ]
    # shellcheck disable=SC2016
    [ "$(yq -r '.jobs.* | select(.uses == "$/.github/workflows/source-security-scan.yml").with."runs-on"' "${path}")" = '${{ inputs.security-runs-on }}' ]
    # shellcheck disable=SC2016
    [ "$(yq -r '.jobs.* | select(.uses == "$/.github/workflows/source-security-scan.yml").with."use-semgrep"' "${path}")" = '${{ inputs.use-semgrep }}' ]
    run ! grep -Fq 'uvx semgrep scan' "${path}"
  done
}

@test "Existing language-specific inclusion patterns are preserved" {
  local workflow path includes
  for workflow in "${WORKFLOWS[@]}"; do
    path="${REPO_ROOT}/.github/workflows/${workflow}"
    includes="$(yq -r '.jobs.* | select(.uses == "$/.github/workflows/source-security-scan.yml").with."semgrep-includes"' "${path}")"
    [ -n "${includes}" ]
    case "${workflow}" in
      python*) [[ "${includes}" == *'*.py'* ]] ;;
      go-*) [[ "${includes}" == *'*.go'* ]] ;;
      typescript*) [[ "${includes}" == *'*.ts'* && "${includes}" == *'*.cjs'* ]] ;;
      html*) [[ "${includes}" == *'*.html'* && "${includes}" == *'*.htm'* ]] ;;
      shell*) [[ "${includes}" == *'*.sh'* && "${includes}" == *'*.bats'* ]] ;;
      terraform*) [[ "${includes}" == *'*.tf'* && "${includes}" == *'*.hcl'* ]] ;;
      docker*) [[ "${includes}" == *'Dockerfile*'* && "${includes}" == *'*.dockerfile'* ]] ;;
      github-actions*) [[ "${includes}" == *'*.yml'* && "${includes}" == *'*.yaml'* ]] ;;
    esac
  done
}

@test "Shared Semgrep execution enforces findings and respects include patterns" {
  prepare_consumer
  run_semgrep_step "${CONSUMER}" "SEMGREP_INCLUDES=*.sh"$'\n'"*.bats"
  [ "${status}" -eq 0 ]
  mapfile -d '' -t args < "${SEMGREP_ARGS}"
  [ "${args[0]}" = semgrep ]
  [ "${args[1]}" = scan ]
  [[ " ${args[*]} " == *' --config p/default --metrics off --error '* ]]
  [[ " ${args[*]} " == *' --include *.sh --include *.bats '* ]]
  [ "${args[-2]}" = -- ]
  [ "${args[-1]}" = . ]
  run_semgrep_step "${CONSUMER}" SEMGREP_EXIT_CODE=1
  [ "${status}" -eq 1 ]
}

@test "Docker Semgrep handles a single file and a directory with spaces" {
  prepare_consumer
  mkdir -p "${CONSUMER}/docker files"
  touch "${CONSUMER}/docker files/Dockerfile"
  for target in 'docker files/Dockerfile' 'docker files'; do
    run_semgrep_step "${CONSUMER}" "SEMGREP_TARGET=${target}"
    [ "${status}" -eq 0 ]
    mapfile -d '' -t args < "${SEMGREP_ARGS}"
    [ "${args[-2]}" = -- ]
    [ "${args[-1]}" = "${target}" ]
  done
}

@test "Shell Semgrep restricts targets to selected tracked files" {
  prepare_consumer
  run_semgrep_step "${CONSUMER}/nested" \
    "SEMGREP_RESTRICT_TO_FILES=true" "SEMGREP_FILE_NAMES=selected file.sh"
  [ "${status}" -eq 0 ]
  mapfile -d '' -t args < "${SEMGREP_ARGS}"
  [ "${args[-2]}" = -- ]
  [ "${args[-1]}" = 'selected file.sh' ]
  [[ " ${args[*]} " != *unrelated.sh* ]]
}

@test "Shell Semgrep skips unmatched selections and rejects an empty file list" {
  prepare_consumer
  run_semgrep_step "${CONSUMER}" \
    "SEMGREP_RESTRICT_TO_FILES=true" "SEMGREP_FILE_NAMES=missing.sh"
  [ "${status}" -eq 0 ]
  [ ! -e "${SEMGREP_ARGS}" ]
  run_semgrep_step "${CONSUMER}" \
    "SEMGREP_RESTRICT_TO_FILES=true" "SEMGREP_FILE_NAMES="
  [ "${status}" -eq 1 ]
  [ ! -e "${SEMGREP_ARGS}" ]
}

@test "Shared Semgrep uses uvx with one-day cooldown and setup-uv caching" {
  run ! grep -q semgrep "${REPO_ROOT}/mise.toml"
  # shellcheck disable=SC2016
  grep -Fq 'uvx "${args[@]}"' "${SCAN_WORKFLOW}"
  [ "$(yq -r '.jobs."source-security-scan".env.UV_EXCLUDE_NEWER' "${SCAN_WORKFLOW}")" = "1 day" ]
  [ "$(yq -r '.jobs."source-security-scan".steps[] | select(.name == "Set up uv for Semgrep") | .with."enable-cache"' "${SCAN_WORKFLOW}")" = auto ]
  run ! grep -Fq SEMGREP_VERSION "${SCAN_WORKFLOW}"
}
