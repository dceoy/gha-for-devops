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
    "$@" bash -euo pipefail "${OSV_SCRIPT}"
}

prepare_download_stub() {
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/download" "${BATS_TEST_TMPDIR}/fixtures"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  export FIXTURE_ASSETS="${BATS_TEST_TMPDIR}/fixtures"
  export CURL_URLS="${BATS_TEST_TMPDIR}/curl-urls"
  (cd "${REPO_ROOT}" && yq -r '.jobs."osv-scan".steps[] | select(.name == "Download OSV-Scanner") | .run' "${WORKFLOW}") > "${BATS_TEST_TMPDIR}/download.sh"
  local arch
  for arch in amd64 arm64; do
    printf '#!/usr/bin/env bash\n# fixture %s\nexit 0\n' "${arch}" > "${FIXTURE_ASSETS}/osv-scanner_linux_${arch}"
  done
  # Exercise Renovate's configured extraction and version/digest replacement together.
  node --input-type=module - "${REPO_ROOT}" "${BATS_TEST_TMPDIR}/download.sh" "${FIXTURE_ASSETS}" "${FIXTURE_VERSION:-v2.7.0}" << 'JS'
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
const [root, script, assets, version] = process.argv.slice(2);
const config = JSON.parse(readFileSync(`${root}/.github/renovate.json`, 'utf8'));
const manager = config.customManagers.find(m => m.datasourceTemplate === 'github-release-attachments');
assert.ok(new RegExp(manager.managerFilePatterns[0].slice(1, -1)).test('.github/workflows/source-security-scan.yml'));
const regex = new RegExp(manager.matchStrings[0], 'g');
const source = readFileSync(script, 'utf8');
const matches = [...source.matchAll(regex)];
assert.equal(matches.length, 2);
const arches = ['amd64', 'arm64'];
let index = 0;
writeFileSync(script, source.replace(regex, (match, ...args) => {
  const groups = args.at(-1);
  assert.equal(groups.depName, 'google/osv-scanner');
  assert.match(groups.currentValue, /^v\d+\.\d+\.\d+$/);
  const digest = createHash('sha256').update(readFileSync(`${assets}/osv-scanner_linux_${arches[index++]}`)).digest('hex');
  return match.replace(groups.currentValue, version).replace(groups.currentDigest, digest);
}));
JS
  cat > "${BATS_TEST_TMPDIR}/bin/curl" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
url="${!#}"
printf '%s\n' "${url}" >> "${CURL_URLS}"
while [[ "$1" != --output ]]; do shift; done
output="$2"
case "${url}" in
  https://github.com/google/osv-scanner/releases/download/"${FIXTURE_VERSION:-v2.7.0}"/osv-scanner_linux_amd64 | https://github.com/google/osv-scanner/releases/download/"${FIXTURE_VERSION:-v2.7.0}"/osv-scanner_linux_arm64) ;;
  *) exit 1 ;;
esac
cp "${FIXTURE_ASSETS}/${url##*/}" "${output}"
if [[ "${TAMPER_BINARY:-false}" == true ]]; then
  printf '# tampered\n' >> "${output}"
fi
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  cd "${BATS_TEST_TMPDIR}/download" || return
}

@test "OSV release installer verifies pinned Linux binaries for supported architectures" {
  local version runner_arch asset_arch
  while read -r version runner_arch asset_arch; do
    export FIXTURE_VERSION="${version}"
    prepare_download_stub
    echo "architecture=${runner_arch}"
    rm -f "${BATS_TEST_TMPDIR}/osv-scanner" "${CURL_URLS}"
    run env RUNNER_OS=Linux "RUNNER_ARCH=${runner_arch}" \
      "RUNNER_TEMP=${BATS_TEST_TMPDIR}" bash -euo pipefail "${BATS_TEST_TMPDIR}/download.sh"
    [ "${status}" -eq 0 ]
    [ -x "${BATS_TEST_TMPDIR}/osv-scanner" ]
    cmp "${FIXTURE_ASSETS}/osv-scanner_linux_${asset_arch}" "${BATS_TEST_TMPDIR}/osv-scanner"
    [ "$(cat "${CURL_URLS}")" = "https://github.com/google/osv-scanner/releases/download/${version}/osv-scanner_linux_${asset_arch}" ]
  done << 'CASES'
v2.7.0 X64 amd64
v2.7.0 ARM64 arm64
v99.0.0 X64 amd64
v99.0.0 ARM64 arm64
CASES
}

@test "OSV release installer rejects tampered binaries before installing" {
  prepare_download_stub
  local arch
  for arch in X64 ARM64; do
    echo "architecture=${arch}"
    rm -f "${BATS_TEST_TMPDIR}/osv-scanner" "${CURL_URLS}"
    run env RUNNER_OS=Linux "RUNNER_ARCH=${arch}" \
      TAMPER_BINARY=true "RUNNER_TEMP=${BATS_TEST_TMPDIR}" bash -euo pipefail "${BATS_TEST_TMPDIR}/download.sh"
    [ "${status}" -ne 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/osv-scanner" ]
    [[ "${output}" == *"FAILED"* ]]
  done
}

@test "OSV release installer rejects unsupported platforms before downloading" {
  prepare_download_stub
  local os arch
  while read -r os arch; do
    echo "platform=${os}/${arch}"
    rm -f "${BATS_TEST_TMPDIR}/osv-scanner" "${CURL_URLS}"
    run env "RUNNER_OS=${os}" "RUNNER_ARCH=${arch}" \
      "RUNNER_TEMP=${BATS_TEST_TMPDIR}" bash -euo pipefail "${BATS_TEST_TMPDIR}/download.sh"
    [ "${status}" -ne 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/osv-scanner" ]
    [ ! -e "${CURL_URLS}" ]
    [[ "${output}" == *"No trusted OSV checksum"* ]]
  done << 'CASES'
Darwin ARM64
Linux ARM
CASES
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
