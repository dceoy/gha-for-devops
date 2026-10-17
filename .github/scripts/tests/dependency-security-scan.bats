#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/dependency-security-scan.yml"
  PREPARE_SCRIPT="${BATS_TEST_TMPDIR}/prepare.sh"
  yq -r '.jobs.scan.steps[] | select(.id == "prepare") | .run' "${WORKFLOW}" > "${PREPARE_SCRIPT}"
}

@test "Dependency scanner uses pinned official OSV and Trivy actions on ubuntu-latest" {
  [ "$(yq -r '.jobs.scan.runs-on' "${WORKFLOW}")" = ubuntu-latest ]
  [ "$(yq -r '.on.workflow_call.inputs."use-osv-scanner".default' "${WORKFLOW}")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."use-trivy".default' "${WORKFLOW}")" = true ]
  grep -Fq 'google/osv-scanner-action/osv-scanner-action@ef6dfdf01765802d5a8dbc3c39852a6128b00af0' "${WORKFLOW}"
  grep -Fq 'aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25' "${WORKFLOW}"
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with."scan-type"' "${WORKFLOW}")" = filesystem ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with."exit-code"' "${WORKFLOW}")" = 1 ]
  grep -Fq 'steps.osv.outcome' "${WORKFLOW}"
  grep -Fq 'steps.trivy.outcome' "${WORKFLOW}"
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
    [ "$(yq -r '.jobs."security-scan".uses' "${path}")" = '$/.github/workflows/dependency-security-scan.yml' ]
    ! grep -Fq 'OSV_SCANNER_VERSION' "${path}"
    ! grep -Fq 'aquasecurity/trivy-action@' "${path}"
  done
}

@test "OSV scanning is skipped when no supported dependency file exists" {
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  export SCAN_PATH="${BATS_TEST_TMPDIR}/empty" REQUIREMENTS_TXT_PATH=""
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/out"
  run bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 0 ]
  [ ! -f "${GITHUB_OUTPUT}" ]
}

@test "OSV preparation detects a nested lockfile under a path with spaces" {
  export SCAN_PATH="${BATS_TEST_TMPDIR}/nested package" REQUIREMENTS_TXT_PATH=""
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/out"
  mkdir -p "${SCAN_PATH}/service"
  touch "${SCAN_PATH}/service/pnpm-lock.yaml"
  run bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -Fxq 'scan=true' "${GITHUB_OUTPUT}"
  grep -Fxq "${SCAN_PATH}" "${GITHUB_OUTPUT}"
  grep -Fxq -- '--recursive' "${GITHUB_OUTPUT}"
  grep -Fxq -- '--include-git-root' "${GITHUB_OUTPUT}"
}

@test "Python requirements override is respected and missing files fail" {
  export SCAN_PATH="${BATS_TEST_TMPDIR}/python" REQUIREMENTS_TXT_PATH="requirements-dev.txt"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/out"
  mkdir -p "${SCAN_PATH}"
  touch "${SCAN_PATH}/requirements-dev.txt"
  run bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -Fxq -- "--lockfile=requirements.txt:${SCAN_PATH}/requirements-dev.txt" "${GITHUB_OUTPUT}"
  rm -f "${SCAN_PATH}/requirements-dev.txt" "${GITHUB_OUTPUT}"
  run bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 1 ]
}

@test "Python uv.lock takes precedence over an explicit requirements override" {
  export SCAN_PATH="${BATS_TEST_TMPDIR}/python" REQUIREMENTS_TXT_PATH="missing.txt"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/out"
  mkdir -p "${SCAN_PATH}"
  touch "${SCAN_PATH}/uv.lock"
  run bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -Fxq 'scan=true' "${GITHUB_OUTPUT}"
  ! grep -Fq -- '--lockfile=' "${GITHUB_OUTPUT}"
}
