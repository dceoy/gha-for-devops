#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/source-security-scan.yml"
  OSV_SCRIPT="${BATS_TEST_TMPDIR}/osv.sh"
  yq -r '.jobs."osv-scan".steps[] | select(.id == "osv") | .run' "${WORKFLOW}" > "${OSV_SCRIPT}"
}

prepare_osv_stub() {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  export DOCKER_ARGS="${BATS_TEST_TMPDIR}/docker-args"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  cat > "${BATS_TEST_TMPDIR}/bin/docker" << 'SH'
#!/usr/bin/env bash
printf '%s\0' "$@" > "${DOCKER_ARGS}"
exit "${DOCKER_EXIT_CODE:-0}"
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/docker"
}

run_osv_scan() {
  local target="$1"
  local requirements="${2:-}"
  shift 2 || :
  run env "SCAN_PATH=${target}" "REQUIREMENTS_TXT_PATH=${requirements}" \
    "GITHUB_WORKSPACE=${BATS_TEST_TMPDIR}" \
    "OSV_IMAGE=ghcr.io/google/osv-scanner:v2.7.0@sha256:4f3b7e2c64b9d38a5febc5a7e4a3dfef1d1362f726dea7a2ef4762b46469fcd0" \
    "$@" bash "${OSV_SCRIPT}"
}

@test "Source scanner isolates Docker OSV on ubuntu-latest from slim filesystem scans" {
  [ "$(yq -r '.on.workflow_call.inputs."runs-on".default' "${WORKFLOW}")" = ubuntu-slim ]
  [ "$(yq -r '.jobs."osv-scan".runs-on' "${WORKFLOW}")" = ubuntu-latest ]
  local runner_expression
  runner_expression="$(yq -r '.jobs.scan.runs-on' "${WORKFLOW}")"
  [[ "${runner_expression}" == *"inputs.runs-on"* ]]
  [ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Run OSV-Scanner") | .name' "${WORKFLOW}")" = "Run OSV-Scanner" ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.name == "Run OSV-Scanner") | .name' "${WORKFLOW}")" = "" ]
  [ "$(yq -r '.on.workflow_call.inputs."use-osv-scanner".default' "${WORKFLOW}")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."use-trivy".default' "${WORKFLOW}")" = true ]
  grep -Fq 'ghcr.io/google/osv-scanner:v2.7.0@sha256:4f3b7e2c64b9d38a5febc5a7e4a3dfef1d1362f726dea7a2ef4762b46469fcd0' "${WORKFLOW}"
  grep -Fq 'aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25' "${WORKFLOW}"
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with."scan-type"' "${WORKFLOW}")" = filesystem ]
  # shellcheck disable=SC2016
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with."exit-code"' "${WORKFLOW}")" = '${{ inputs.trivy-exit-code }}' ]
  [ "$(yq -r '.on.workflow_call.inputs."trivy-exit-code".default' "${WORKFLOW}")" = 1 ]
  [ "$(yq -r '.jobs."osv-scan".steps[] | select(.id == "osv") | .shell' "${WORKFLOW}")" = bash ]
  grep -Fq 'steps.trivy.outcome' "${WORKFLOW}"
  grep -Fq 'steps.semgrep.outcome' "${WORKFLOW}"
  [ "$(yq -r '.on.workflow_call.inputs."use-semgrep".default' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with.format' "${WORKFLOW}")" = sarif ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with."limit-severities-for-sarif"' "${WORKFLOW}")" = true ]
  # shellcheck disable=SC2016
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with.severity' "${WORKFLOW}")" = '${{ inputs.trivy-severity }}' ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.name == "Upload Trivy SARIF report") | .with."if-no-files-found"' "${WORKFLOW}")" = warn ]
}

@test "Package lint workflows delegate optional scans to the shared workflow" {
  for name in go python typescript html; do
    case "${name}" in
      go) file=go-package-lint-and-scan.yml ;;
      python) file=python-package-lint-and-scan.yml ;;
      typescript) file=typescript-package-lint-and-scan.yml ;;
      html) file=html-lint-and-scan.yml ;;
    esac
    path="${REPO_ROOT}/.github/workflows/${file}"
    [ "$(yq -r '.on.workflow_call.inputs."use-osv-scanner".default' "${path}")" = true ]
    [ "$(yq -r '.on.workflow_call.inputs."use-trivy".default' "${path}")" = true ]
    [ "$(yq -r '.jobs."security-scan".uses' "${path}")" = '$/.github/workflows/source-security-scan.yml' ]
    ! grep -Fq 'OSV_SCANNER_VERSION' "${path}"
    ! grep -Fq 'aquasecurity/trivy-action@' "${path}"
  done
}

@test "OSV scans arbitrary ecosystems and preserves the target as one argument" {
  prepare_osv_stub
  local target="${BATS_TEST_TMPDIR}/other ecosystems"
  mkdir -p "${target}/nested"
  touch "${target}/pom.xml" "${target}/nested/packages.lock.json" \
    "${target}/renv.lock" "${target}/nested/bom.cdx.json"
  run_osv_scan "${target}" ""
  [ "${status}" -eq 0 ]
  mapfile -d '' -t args < "${DOCKER_ARGS}"
  [ "${args[-1]}" = "${target}" ]
  [ "${args[-2]}" = --include-git-root ]
  [ "${args[-3]}" = --recursive ]
  [ "${args[-4]}" = source ]
  [ "${args[-5]}" = scan ]
}

@test "OSV handles an empty directory without failing on no dependencies" {
  prepare_osv_stub
  local target="${BATS_TEST_TMPDIR}/empty"
  mkdir -p "${target}"
  run_osv_scan "${target}" "" DOCKER_EXIT_CODE=128
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"no dependencies"* ]]
  mapfile -d '' -t args < "${DOCKER_ARGS}"
  [ "${args[-1]}" = "${target}" ]
}

@test "OSV preserves nested custom requirements paths containing spaces" {
  prepare_osv_stub
  local target="${BATS_TEST_TMPDIR}/nested package"
  local file="requirements/prod requirements.txt"
  mkdir -p "${target}/requirements"
  touch "${target}/${file}"
  run_osv_scan "${target}" "${file}"
  [ "${status}" -eq 0 ]
  mapfile -d '' -t args < "${DOCKER_ARGS}"
  [ "${args[-1]}" = "${target}" ]
  [ "${args[-2]}" = "--lockfile=requirements.txt:${target}/${file}" ]
  [ "${args[-3]}" = --include-git-root ]
}

@test "OSV rejects nonexistent custom requirements" {
  prepare_osv_stub
  local target="${BATS_TEST_TMPDIR}/python"
  mkdir -p "${target}"
  run_osv_scan "${target}" "missing requirements.txt"
  [ "${status}" -eq 1 ]
  [ ! -f "${DOCKER_ARGS}" ]
}

@test "OSV defers a requirements override to a present uv.lock" {
  prepare_osv_stub
  local target="${BATS_TEST_TMPDIR}/python"
  mkdir -p "${target}"
  touch "${target}/uv.lock"
  run_osv_scan "${target}" "missing requirements.txt"
  [ "${status}" -eq 0 ]
  mapfile -d '' -t args < "${DOCKER_ARGS}"
  [ "${args[-1]}" = "${target}" ]
  [ "${args[-2]}" = --include-git-root ]
}

@test "OSV preserves vulnerability and execution failure exit codes" {
  prepare_osv_stub
  local target="${BATS_TEST_TMPDIR}/python"
  mkdir -p "${target}"
  run_osv_scan "${target}" "" DOCKER_EXIT_CODE=1
  [ "${status}" -eq 1 ]
  run_osv_scan "${target}" "" DOCKER_EXIT_CODE=2
  [ "${status}" -eq 2 ]
}
