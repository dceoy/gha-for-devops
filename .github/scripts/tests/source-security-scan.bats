#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/source-security-scan.yml"
  OSV_SCRIPT="${BATS_TEST_TMPDIR}/osv.sh"
  yq -r '.jobs."osv-scan".steps[] | select(.id == "osv") | .run' "${WORKFLOW}" > "${OSV_SCRIPT}"
}

prepare_osv_stub() {
  export OSV_ARGS="${BATS_TEST_TMPDIR}/osv-args"
  cat > "${BATS_TEST_TMPDIR}/osv-scanner" << 'SH'
#!/usr/bin/env bash
printf '%s\0' "$@" > "${OSV_ARGS}"
exit "${OSV_EXIT_CODE:-0}"
SH
  chmod +x "${BATS_TEST_TMPDIR}/osv-scanner"
}

run_osv_scan() {
  local target="$1"
  local requirements="${2:-}"
  shift 2 || :
  cd "${BATS_TEST_TMPDIR}" || return
  run env "SCAN_PATH=${target}" "REQUIREMENTS_TXT_PATH=${requirements}" \
    "GITHUB_WORKSPACE=${BATS_TEST_TMPDIR}" \
    "RUNNER_TEMP=${BATS_TEST_TMPDIR}" \
    "$@" bash "${OSV_SCRIPT}"
}

prepare_download_stub() {
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/download"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  yq -r '.jobs."osv-scan".steps[] | select(.name == "Download OSV-Scanner") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/download.sh"
  cat > "${BATS_TEST_TMPDIR}/bin/curl" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
url="${!#}"
while [[ "$1" != --output ]]; do shift; done
output="$2"
if [[ "${url}" == */osv-scanner_SHA256SUMS ]]; then
  for asset in osv-scanner_linux_amd64 osv-scanner_linux_arm64; do
    [[ -f "${asset}" ]] || continue
    case "${CHECKSUM_MODE:-valid}" in
      valid) sha256sum "${asset}" ;;
      mismatch) printf '%064d  %s\n' 0 "${asset}" ;;
      missing) : ;;
      malformed) printf 'invalid  %s\n' "${asset}" ;;
      duplicate) sha256sum "${asset}" "${asset}" ;;
    esac
  done > "${output}"
else
  printf '#!/usr/bin/env bash\nexit 0\n' > "${output}"
fi
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  cd "${BATS_TEST_TMPDIR}/download" || return
}

@test "OSV release installer verifies Linux binaries for supported architectures" {
  prepare_download_stub
  local arch
  for arch in X64 ARM64; do
    run env RUNNER_OS=Linux "RUNNER_ARCH=${arch}" OSV_SCANNER_VERSION=2.7.0 \
      "RUNNER_TEMP=${BATS_TEST_TMPDIR}" bash "${BATS_TEST_TMPDIR}/download.sh"
    [ "${status}" -eq 0 ]
    [ -x "${BATS_TEST_TMPDIR}/osv-scanner" ]
    rm "${BATS_TEST_TMPDIR}/osv-scanner"
  done
}

@test "OSV release installer rejects invalid checksums before installing" {
  prepare_download_stub
  local mode
  for mode in mismatch missing malformed duplicate; do
    run env RUNNER_OS=Linux RUNNER_ARCH=X64 OSV_SCANNER_VERSION=2.7.0 \
      "CHECKSUM_MODE=${mode}" "RUNNER_TEMP=${BATS_TEST_TMPDIR}" bash "${BATS_TEST_TMPDIR}/download.sh"
    [ "${status}" -ne 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/osv-scanner" ]
  done
}

@test "Source scanner downloads native OSV and delegates Trivy to the read-only core" {
  [ "$(yq -r '.on.workflow_call.inputs."runs-on".default' "$WORKFLOW")" = ubuntu-slim ]
  [ "$(yq -r '.jobs."osv-scan".runs-on' "$WORKFLOW")" = "\${{ inputs.runs-on }}" ]
  [ "$(yq -r '.jobs."trivy-scan".uses' "$WORKFLOW")" = '$/.github/workflows/trivy-scan.yml' ]
  [ "$(yq -r '.jobs."trivy-scan".with."scan-type"' "$WORKFLOW")" = filesystem ]
  [ "$(yq -r '.jobs."trivy-scan".with."report-format"' "$WORKFLOW")" = sarif ]
  [ "$(yq -r '.on.workflow_call.inputs."use-osv-scanner".default' "$WORKFLOW")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."use-trivy".default' "$WORKFLOW")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."trivy-exit-code".default' "$WORKFLOW")" = 1 ]
  [ "$(yq -r '.on.workflow_call.inputs."use-semgrep".default' "$WORKFLOW")" = false ]
  run ! grep -Fq 'mise' "$WORKFLOW"
  [ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Set up Go for call analysis") | .uses' "$WORKFLOW")" = actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e ]
  [ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Set up Go for call analysis") | .with."go-version"' "$WORKFLOW")" = stable ]
  [ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Set up Go for call analysis") | .with.cache' "$WORKFLOW")" = false ]
  local setup_index scan_index
  setup_index="$(yq -r '.jobs."osv-scan".steps | to_entries[] | select(.value.name == "Set up Go for call analysis") | .key' "$WORKFLOW")"
  scan_index="$(yq -r '.jobs."osv-scan".steps | to_entries[] | select(.value.id == "osv") | .key' "$WORKFLOW")"
  [ "${setup_index}" -lt "${scan_index}" ]
  run ! grep -Fq 'OSV_IMAGE:' "$WORKFLOW"
  run ! grep -Fq 'aquasecurity/trivy-action@' "$WORKFLOW"
  grep -Fq 'steps.semgrep.outcome' "$WORKFLOW"
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
  mapfile -d '' -t args < "${OSV_ARGS}"
  [ "${args[-1]}" = "${target}" ]
  [ "${args[-2]}" = --include-git-root ]
  [ "${args[-3]}" = --recursive ]
  [ "${args[-4]}" = source ]
  [ "${args[-5]}" = scan ]
}

@test "OSV accepts workspace-relative scan paths" {
  prepare_osv_stub
  mkdir -p "${BATS_TEST_TMPDIR}/relative package"
  run_osv_scan "relative package" ""
  [ "${status}" -eq 0 ]
  mapfile -d '' -t args < "${OSV_ARGS}"
  [ "${args[-1]}" = "relative package" ]
}

@test "OSV handles an empty directory without failing on no dependencies" {
  prepare_osv_stub
  local target="${BATS_TEST_TMPDIR}/empty"
  mkdir -p "${target}"
  run_osv_scan "${target}" "" OSV_EXIT_CODE=128
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"no dependencies"* ]]
  mapfile -d '' -t args < "${OSV_ARGS}"
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
  mapfile -d '' -t args < "${OSV_ARGS}"
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
  [ ! -f "${OSV_ARGS}" ]
}

@test "OSV defers a requirements override to a present uv.lock" {
  prepare_osv_stub
  local target="${BATS_TEST_TMPDIR}/python"
  mkdir -p "${target}"
  touch "${target}/uv.lock"
  run_osv_scan "${target}" "missing requirements.txt"
  [ "${status}" -eq 0 ]
  mapfile -d '' -t args < "${OSV_ARGS}"
  [ "${args[-1]}" = "${target}" ]
  [ "${args[-2]}" = --include-git-root ]
}

@test "OSV preserves vulnerability and execution failure exit codes" {
  prepare_osv_stub
  local target="${BATS_TEST_TMPDIR}/python"
  mkdir -p "${target}"
  run_osv_scan "${target}" "" OSV_EXIT_CODE=1
  [ "${status}" -eq 1 ]
  run_osv_scan "${target}" "" OSV_EXIT_CODE=2
  [ "${status}" -eq 2 ]
}
