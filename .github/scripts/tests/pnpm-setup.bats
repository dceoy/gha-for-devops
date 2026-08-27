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
    ".jobs.*.steps[] | select(.uses | test(\"^pnpm/action-setup@\")) | .with.${key}" \
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
  done < <(grep -rl --include='*.yml' 'pnpm/action-setup@' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "pnpm setup preserves latest fallback without package metadata" {
  local count=0
  while IFS= read -r workflow; do
    [[ "${workflow}" == */bats-test.yml ]] && continue
    run grep -F "echo 'PNPM_VERSION=latest'" "${workflow}"
    [ "${status}" -eq 0 ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'pnpm/action-setup@' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "Bats workflow uses latest uv and pnpm with minimum release age" {
  local workflow="${WORKFLOWS}/bats-test.yml"

  run yq -r '.env.UV_EXCLUDE_NEWER' "${workflow}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "7 days" ]

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
  run pnpm_setup_value "${WORKFLOWS}/bats-test.yml" package_json_file
  [ "${status}" -eq 0 ]
  [ "${output}" = "package.json" ]
}

@test "nested pnpm projects resolve package.json from package-path" {
  local count=0
  while IFS= read -r workflow; do
    [[ "${workflow}" == */bats-test.yml ]] && continue
    run pnpm_setup_value "${workflow}" package_json_file
    [ "${status}" -eq 0 ]
    [ "${output}" = "\${{ format('{0}/package.json', inputs.package-path) }}" ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'pnpm/action-setup@' "${WORKFLOWS}")
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
