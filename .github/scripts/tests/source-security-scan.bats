#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/source-security-scan.yml"
  PREPARE_SCRIPT="${BATS_TEST_TMPDIR}/prepare.sh"
  yq -r '.jobs."osv-scan".steps[] | select(.id == "prepare") | .run' "${WORKFLOW}" > "${PREPARE_SCRIPT}"
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
  grep -Fq 'google/osv-scanner-action/osv-scanner-action@b1d267aea5211fa648d9d442fa64b90dbdcbdd36' "${WORKFLOW}"
  grep -Fq 'aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25' "${WORKFLOW}"
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with."scan-type"' "${WORKFLOW}")" = filesystem ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with."exit-code"' "${WORKFLOW}")" = 1 ]
  grep -Fq 'steps.osv.outcome' "${WORKFLOW}"
  grep -Fq 'steps.trivy.outcome' "${WORKFLOW}"
  grep -Fq 'steps.semgrep.outcome' "${WORKFLOW}"
  [ "$(yq -r '.on.workflow_call.inputs."use-semgrep".default' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.jobs.scan.steps[] | select(.id == "trivy") | .with.format' "${WORKFLOW}")" = sarif ]
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

@test "OSV scanning is skipped when no supported dependency file exists" {
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  local scan_path="${BATS_TEST_TMPDIR}/empty"
  local output_file="${BATS_TEST_TMPDIR}/out"
  run env SCAN_PATH="${scan_path}" REQUIREMENTS_TXT_PATH="" GITHUB_OUTPUT="${output_file}" bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 0 ]
  [ ! -f "${output_file}" ]
}

@test "OSV preparation detects a nested lockfile under a path with spaces" {
  local scan_path="${BATS_TEST_TMPDIR}/nested package"
  local output_file="${BATS_TEST_TMPDIR}/out"
  mkdir -p "${scan_path}/service"
  touch "${scan_path}/service/pnpm-lock.yaml"
  run env SCAN_PATH="${scan_path}" REQUIREMENTS_TXT_PATH="" GITHUB_OUTPUT="${output_file}" bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -Fxq 'scan=true' "${output_file}"
  grep -Fxq "${scan_path}" "${output_file}"
  grep -Fxq -- '--recursive' "${output_file}"
  grep -Fxq -- '--include-git-root' "${output_file}"
}

@test "Python requirements override is respected and missing files fail" {
  local scan_path="${BATS_TEST_TMPDIR}/python"
  local output_file="${BATS_TEST_TMPDIR}/out"
  mkdir -p "${scan_path}"
  touch "${scan_path}/requirements-dev.txt"
  run env SCAN_PATH="${scan_path}" REQUIREMENTS_TXT_PATH="requirements-dev.txt" GITHUB_OUTPUT="${output_file}" bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -Fxq -- "--lockfile=requirements.txt:${scan_path}/requirements-dev.txt" "${output_file}"
  rm -f "${scan_path}/requirements-dev.txt" "${output_file}"
  run env SCAN_PATH="${scan_path}" REQUIREMENTS_TXT_PATH="requirements-dev.txt" GITHUB_OUTPUT="${output_file}" bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 1 ]
}

@test "Python uv.lock takes precedence over an explicit requirements override" {
  local scan_path="${BATS_TEST_TMPDIR}/python"
  local output_file="${BATS_TEST_TMPDIR}/out"
  mkdir -p "${scan_path}"
  touch "${scan_path}/uv.lock"
  run env SCAN_PATH="${scan_path}" REQUIREMENTS_TXT_PATH="missing.txt" GITHUB_OUTPUT="${output_file}" bash "${PREPARE_SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -Fxq 'scan=true' "${output_file}"
  run ! grep -Fq -- '--lockfile=' "${output_file}"
}
