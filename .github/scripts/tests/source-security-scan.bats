#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/source-security-scan.yml"
  MISE_VERSION="$(yq -r '.jobs."osv-scan".env.MISE_VERSION' "${WORKFLOW}")"
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

prepare_mise_stub() {
  export MISE_LOG="${BATS_TEST_TMPDIR}/mise-log"
  mkdir -p "${BATS_TEST_TMPDIR}/stub-bin"
  cat > "${BATS_TEST_TMPDIR}/stub-bin/mise" << 'SH'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "${PWD}" "${MISE_LOCKED:-}" "$*" >> "${MISE_LOG}"
case "$1" in
  trust) ;;
  install) cp mise.lock "${MISE_LOG}.lock" ;;
  which) [[ "$2" == osv-scanner ]] && echo "${PWD}/installs/osv-scanner" ;;
  *) exit 1 ;;
esac
SH
  chmod +x "${BATS_TEST_TMPDIR}/stub-bin/mise"
}

run_osv_scan() {
  local target="$1"
  local requirements="${2:-}"
  shift 2 || :
  cd "${BATS_TEST_TMPDIR}" || return
  run env "SCAN_PATH=${target}" "REQUIREMENTS_TXT_PATH=${requirements}" \
    "GITHUB_WORKSPACE=${BATS_TEST_TMPDIR}" \
    "OSV_SCANNER_BIN=${BATS_TEST_TMPDIR}/osv-scanner" \
    "$@" bash -euo pipefail "${OSV_SCRIPT}"
}

@test "OSV-Scanner is installed by mise outside the checkout from a trusted per-platform lock" {
  prepare_mise_stub
  local step='.jobs."osv-scan".steps[] | select(.name == "Install OSV-Scanner")'
  [[ "${MISE_VERSION}" =~ ^[0-9]{4}\.[0-9]+\.[0-9]+$ ]]
  [[ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Set up mise") | .uses' "${WORKFLOW}")" =~ ^jdx/mise-action@[a-f0-9]{40}$ ]]
  [ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Set up mise") | .with.install' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Set up mise") | .with.version' "${WORKFLOW}")" = "\${{ env.MISE_VERSION }}" ]
  [ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Set up mise") | .with.cache' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Set up mise") | .with.working_directory' "${WORKFLOW}")" = "\${{ runner.temp }}" ]
  [ "$(yq -r "${step} | .\"working-directory\"" "${WORKFLOW}")" = "\${{ runner.temp }}" ]
  [ "$(yq -r "${step} | .env.MISE_LOCKED" "${WORKFLOW}")" = true ]
  yq -r "${step} | .run" "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/install.sh"
  local case_row os_arch platform asset checksum
  for case_row in "X64 linux-x64 osv-scanner_linux_amd64" "ARM64 linux-arm64 osv-scanner_linux_arm64"; do
    read -r os_arch platform asset <<< "${case_row}"
    rm -f "${MISE_LOG}" "${MISE_LOG}.lock"
    mkdir -p "${BATS_TEST_TMPDIR}/checkout" "${BATS_TEST_TMPDIR}/runner-temp"
    : > "${BATS_TEST_TMPDIR}/github-env"
    run env "PATH=${BATS_TEST_TMPDIR}/stub-bin:${PATH}" "RUNNER_OS=Linux" "RUNNER_ARCH=${os_arch}" \
      "RUNNER_TEMP=${BATS_TEST_TMPDIR}/runner-temp" "GITHUB_ENV=${BATS_TEST_TMPDIR}/github-env" \
      "MISE_LOCKED=true" bash -euo pipefail "${BATS_TEST_TMPDIR}/install.sh"
    [ "${status}" -eq 0 ]
    checksum="$(grep -E "^\[tools\.\"aqua:google/osv-scanner\"\.\"platforms\.${platform}\"\]" -A1 "${MISE_LOG}.lock" | sed -n 's/^checksum = "sha256:\([a-f0-9]\{64\}\)"$/\1/p')"
    [[ "${checksum}" =~ ^[a-f0-9]{64}$ ]]
    grep -Fq "url = \"https://github.com/google/osv-scanner/releases/download/v" "${MISE_LOG}.lock"
    grep -Fq "/${asset}\"" "${MISE_LOG}.lock"
    # Every mise call runs in the trusted directory, never in the caller checkout, with locked installs.
    while IFS='|' read -r dir locked _; do
      [ "${dir}" = "${BATS_TEST_TMPDIR}/runner-temp/osv-scanner-mise" ]
      [ "${locked}" = true ]
    done < "${MISE_LOG}"
    grep -Fq "|install" "${MISE_LOG}"
    grep -Fxq "OSV_SCANNER_BIN=${BATS_TEST_TMPDIR}/runner-temp/osv-scanner-mise/installs/osv-scanner" "${BATS_TEST_TMPDIR}/github-env"
  done
  run env "PATH=${BATS_TEST_TMPDIR}/stub-bin:${PATH}" "RUNNER_OS=Linux" "RUNNER_ARCH=ARM" \
    "RUNNER_TEMP=${BATS_TEST_TMPDIR}/runner-temp" "GITHUB_ENV=${BATS_TEST_TMPDIR}/github-env" \
    bash -euo pipefail "${BATS_TEST_TMPDIR}/install.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No trusted OSV checksum"* ]]
  run ! grep -Fq 'mise exec' "${WORKFLOW}"
}

@test "Renovate extracts the OSV-Scanner release versions with checksums and the mise version" {
  node --input-type=module - "${REPO_ROOT}" << 'JS'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const root = process.argv[2];
const cfg = JSON.parse(readFileSync(`${root}/.github/renovate.json`, 'utf8'));
const workflow = readFileSync(`${root}/.github/workflows/source-security-scan.yml`, 'utf8');
const find = description => cfg.customManagers.find(m => m.description === description);
const envManager = find('Update tool versions declared in GitHub Actions workflow env blocks');
const osvManager = find('Update OSV-Scanner release versions together with architecture-specific checksums');
assert.ok(envManager && osvManager);
const miseVersion = workflow.match(/^\s*MISE_VERSION:\s*(\S+)/m)?.[1];
assert.match(miseVersion ?? '', /^\d+(?:\.\d+){2}$/);
const envMatches = [...workflow.matchAll(new RegExp(envManager.matchStrings[0], 'g'))];
assert.ok(envMatches.some(m => m.groups.depName === 'jdx/mise' && m.groups.currentValue === miseVersion));
assert.equal(osvManager.datasourceTemplate, 'github-release-attachments');
const osvMatches = [...workflow.matchAll(new RegExp(osvManager.matchStrings[0], 'g'))];
assert.equal(osvMatches.length, 2);
for (const m of osvMatches) {
  assert.equal(m.groups.depName, 'google/osv-scanner');
  assert.match(m.groups.currentValue, /^v\d+(?:\.\d+){2}$/);
  assert.match(m.groups.currentDigest, /^[a-f0-9]{64}$/);
}
assert.equal(new Set(osvMatches.map(m => m.groups.currentValue)).size, 1);
JS
}

@test "Source scanner uses mise for OSV and delegates Trivy to the read-only core" {
  [ "$(yq -r '.on.workflow_call.inputs."runs-on".default' "$WORKFLOW")" = ubuntu-slim ]
  [ "$(yq -r '.jobs."osv-scan".runs-on' "$WORKFLOW")" = "\${{ inputs.runs-on }}" ]
  [ "$(yq -r '.jobs."trivy-scan".uses' "$WORKFLOW")" = '$/.github/workflows/trivy-scan.yml' ]
  [ "$(yq -r '.jobs."trivy-scan".with."scan-type"' "$WORKFLOW")" = filesystem ]
  [ "$(yq -r '.jobs."trivy-scan".with."report-format"' "$WORKFLOW")" = sarif ]
  [ "$(yq -r '.on.workflow_call.inputs."use-osv-scanner".default' "$WORKFLOW")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."use-trivy".default' "$WORKFLOW")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."trivy-exit-code".default' "$WORKFLOW")" = 1 ]
  [ "$(yq -r '.on.workflow_call.inputs."use-semgrep".default' "$WORKFLOW")" = false ]
  grep -Fq "\"\${OSV_SCANNER_BIN}\" \"\${args[@]}\"" "$WORKFLOW"
  [[ "$(yq -r '.jobs."osv-scan".steps[] | select(.name == "Set up Go for call analysis") | .uses' "$WORKFLOW")" =~ ^actions/setup-go@[a-f0-9]{40}$ ]]
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
