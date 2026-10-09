#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORKFLOWS="${REPO_ROOT}/.github/workflows"
  FIXTURES="${REPO_ROOT}/.github/fixtures/pnpm"
}

pnpm_setup_value() {
  local workflow="$1" key="$2"
  yq -r \
    ".jobs.*.steps[] | select(.uses | test(\"^pnpm/setup@\")) | .with.${key}" \
    "${workflow}"
}

has_pnpm_version_source_in_fixture() {
  local workflow="$1" fixture_dir="$2"
  local fn
  fn="$(
    yq -r '.jobs.*.steps[] | select(.run != null and (.run | test("has_pnpm_version_source"))) | .run' \
      "${workflow}" \
      | awk '/^has_pnpm_version_source\(\) \{$/{flag=1} flag{print} flag && /^}$/{exit}'
  )"
  [ -n "${fn}" ] || return 1
  (
    cd "${fixture_dir}" || exit 1
    eval "${fn}"
    has_pnpm_version_source
  )
}

@test "pnpm version defaults to package.json in every exposed input" {
  local count=0
  while IFS= read -r workflow; do
    run yq -r '.on.workflow_call.inputs.pnpm-version.default' "${workflow}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' '^      pnpm-version:$' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "explicit pnpm version remains an action override" {
  local count=0
  while IFS= read -r workflow; do
    [[ "${workflow}" == */bats-test.yml ]] && continue
    run pnpm_setup_value "${workflow}" version
    [ "${status}" -eq 0 ]
    [ "${output}" = "\${{ inputs.pnpm-version || env.PNPM_VERSION }}" ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'pnpm/setup@' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "pnpm setup preserves latest fallback without package metadata" {
  local count=0
  while IFS= read -r workflow; do
    [[ "${workflow}" == */bats-test.yml ]] && continue
    run grep -F "echo 'PNPM_VERSION=latest'" "${workflow}"
    [ "${status}" -eq 0 ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'pnpm/setup@' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "Bats workflow uses latest uv and pnpm with minimum release age" {
  local workflow="${WORKFLOWS}/bats-test.yml"

  run yq -r '.env.UV_EXCLUDE_NEWER' "${workflow}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "7 days" ]

  run grep -F 'npm_config_min_release_age:' "${workflow}"
  [ "${status}" -ne 0 ]

  run yq -r '.env.NPM_CONFIG_MIN_RELEASE_AGE' "${workflow}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  run yq -r '.env.PNPM_CONFIG_MINIMUM_RELEASE_AGE' "${workflow}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "10080" ]

  run yq -r '.jobs.*.steps[] | select(.uses | test("^astral-sh/setup-uv@")) | .with.version' "${workflow}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "latest" ]

  run pnpm_setup_value "${workflow}" version
  [ "${status}" -eq 0 ]
  [ "${output}" = "latest" ]
}

@test "root pnpm project resolves the root package.json" {
  run pnpm_setup_value "${WORKFLOWS}/bats-test.yml" working-directory
  [ "${status}" -eq 0 ]
  [ "${output}" = "." ]
}

@test "nested pnpm projects resolve package.json from package-path" {
  local count=0
  while IFS= read -r workflow; do
    [[ "${workflow}" == */bats-test.yml ]] && continue
    run pnpm_setup_value "${workflow}" working-directory
    [ "${status}" -eq 0 ]
    [ "${output}" = "\${{ inputs.package-path }}" ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'pnpm/setup@' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "pnpm version detector finds devEngines.packageManager behind a preceding nested property" {
  local count=0
  while IFS= read -r workflow; do
    run has_pnpm_version_source_in_fixture "${workflow}" "${FIXTURES}/devengines-nested-property-precedes"
    [ "${status}" -eq 0 ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'has_pnpm_version_source() {' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "pnpm version detector reports no source when the manifest has none" {
  local count=0
  while IFS= read -r workflow; do
    run has_pnpm_version_source_in_fixture "${workflow}" "${FIXTURES}/no-version-source"
    [ "${status}" -ne 0 ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'has_pnpm_version_source() {' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "Bats runtime selection prefers manifest declarations and validates them" {
  local script fixture expected
  script="$(yq -r '.jobs.test.steps[] | select(.id == "pnpm-config") | .run' "${WORKFLOWS}/bats-test.yml")"
  mkdir -p "${BATS_TEST_TMPDIR}/runtime"
  while IFS='|' read -r fixture expected; do
    printf '%s\n' "${fixture}" > "${BATS_TEST_TMPDIR}/runtime/package.json"
    : > "${BATS_TEST_TMPDIR}/runtime/output"
    run bash -euo pipefail -c 'cd "$1"; export NODE_VERSION=latest GITHUB_OUTPUT="$1/output"; eval "$2"' -- "${BATS_TEST_TMPDIR}/runtime" "${script}"
    [ "${status}" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/runtime/output")" = "node-version=${expected}" ]
  done << 'CASES'
{}|latest
{"engines":{"node":"^22"}}|^22
{"devEngines":{"runtime":{"name":"node","version":"24.4.0"}},"engines":{"node":"22"}}|24.4.0
{"devEngines":{"runtime":[{"name":"bun","version":"1"},{"name":"node","version":"^24"}]}}|^24
CASES
  printf '%s\n' '{"devEngines":{"runtime":{"name":"node","version":""}}}' > "${BATS_TEST_TMPDIR}/runtime/package.json"
  run bash -euo pipefail -c 'cd "$1"; export NODE_VERSION=latest GITHUB_OUTPUT="$1/output"; eval "$2"' -- "${BATS_TEST_TMPDIR}/runtime" "${script}"
  [ "${status}" -ne 0 ]
  rm "${BATS_TEST_TMPDIR}/runtime/package.json"
  : > "${BATS_TEST_TMPDIR}/runtime/output"
  run bash -euo pipefail -c 'cd "$1"; export NODE_VERSION=latest GITHUB_OUTPUT="$1/output"; eval "$2"' -- "${BATS_TEST_TMPDIR}/runtime" "${script}"
  [ "${status}" -eq 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/runtime/output")" = "node-version=latest" ]
}

@test "Bats pnpm cache reuses only entries scoped to the same salt" {
  local workflow="${WORKFLOWS}/bats-test.yml" key restore_keys
  key="$(yq -r '.jobs.test.steps[] | select(.name == "Cache salted pnpm store") | .with.key' "${workflow}")"
  restore_keys="$(yq -r '.jobs.test.steps[] | select(.name == "Cache salted pnpm store") | .with.restore-keys' "${workflow}")"
  # shellcheck disable=SC2016
  [[ "${key}" == *'${{ inputs.cache-salt }}'* ]]
  # shellcheck disable=SC2016
  [[ "${restore_keys}" == *'${{ inputs.cache-salt }}-' ]]
  run yq -r '.jobs.test.steps[] | select(.name == "Cache salted pnpm store") | .if' "${workflow}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "inputs.enable-cache && inputs.cache-salt != ''" ]
}

@test "pnpm/setup installs Node.js without a second setup-node step" {
  local workflow count=0
  while IFS= read -r workflow; do
    run pnpm_setup_value "${workflow}" runtime
    [ "${status}" -eq 0 ]
    [ "${output}" = "node@\${{ steps.pnpm-config.outputs.node-version }}" ]
    run yq -r '.jobs.*.steps[] | select(.uses | test("^actions/setup-node@")) | .if // ""' "${workflow}"
    [ "${status}" -eq 0 ]
    if [[ "${workflow}" == */bats-test.yml ]]; then
      [ -z "${output}" ]
    else
      [[ "${output}" == *"steps.pnpm-config.outputs.legacy == 'true'"* ]]
      [[ "${output}" == *"env.PACKAGE_MANAGER != 'pnpm'"* ]]
      [[ "${output}" != *"steps.pnpm-config.outputs.legacy != 'true'"* ]]
    fi
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'pnpm/setup@' "${WORKFLOWS}")
  [ "${count}" -eq 5 ]
}

@test "pnpm 11 Intel macOS validates the actual Node.js runtime before caching" {
  local workflow script node_version expected count=0
  while IFS= read -r workflow; do
    script="$(yq -r '.jobs.*.steps[] | select(.name == "Validate pnpm 11 Node.js runtime on Intel macOS") | .run' "${workflow}")"
    [ -n "${script}" ]
    run yq -r '.jobs.*.steps[] | select(.name == "Validate pnpm 11 Node.js runtime on Intel macOS") | .if' "${workflow}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "steps.legacy-pnpm.outputs.major == '11'" ]
    run yq -r '.jobs.*.steps[] | select(.name == "Record pnpm version on Intel macOS") | .if' "${workflow}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "env.PACKAGE_MANAGER == 'pnpm' && steps.pnpm-config.outputs.legacy == 'true' && runner.os == 'macOS' && runner.arch == 'X64'" ]
    run yq -r '.jobs.*.steps[] | select(.name == "Setup Node.js for legacy pnpm") | .with.cache' "${workflow}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "\${{ inputs.enable-cache && steps.legacy-pnpm.outputs.major != '11' && 'pnpm' || '' }}" ]
    run yq -r '.jobs.*.steps[] | select(.name == "Cache pnpm 11 store on Intel macOS") | .if' "${workflow}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "inputs.enable-cache && steps.legacy-pnpm.outputs.major == '11'" ]
    while IFS='|' read -r node_version expected; do
      # shellcheck disable=SC2016
      run env TEST_NODE_VERSION="${node_version}" bash -euo pipefail -c 'node() { printf "v%s\\n" "${TEST_NODE_VERSION}"; }; eval "$1"' -- "${script}"
      if [[ "${expected}" == pass ]]; then
        [ "${status}" -eq 0 ]
      else
        [ "${status}" -ne 0 ]
        [[ "${output}" == *"pnpm 11 on Intel macOS requires Node.js >=22.13.0"* ]]
      fi
    done << 'CASES'
20.19.0|fail
22.12.9|fail
22.13.0|pass
22.14.0|pass
24.0.0|pass
CASES
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'Setup legacy pnpm' "${WORKFLOWS}")
  [ "${count}" -eq 4 ]
}
