#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  GUARD="${REPO_ROOT}/.agents/skills/local-qa/scripts/check-qa-dependencies.sh"
  cp "${REPO_ROOT}/pyproject.toml" "${REPO_ROOT}/uv.lock" "${BATS_TEST_TMPDIR}/"
  cd "${BATS_TEST_TMPDIR}" || return
}

@test "QA assessment accepts the reviewed dev-only verification dependency graph" {
  run bash "${GUARD}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'unaffected signature verification'* ]]
}

@test "QA assessment tolerates Checkov lockfile version updates" {
  local checkov_version
  checkov_version="$(yq -p toml -o json "${REPO_ROOT}/uv.lock" | jq -r '.package[] | select(.name == "checkov") | .version')"
  sed "s/version = \"${checkov_version}\"/version = \"${checkov_version}.1\"/" "${REPO_ROOT}/uv.lock" > uv.lock
  run bash "${GUARD}"
  [ "${status}" -eq 0 ]
}

@test "QA assessment rejects changed reviewed ecdsa versions and artifacts" {
  local lock_json original replacement
  lock_json="$(yq -p toml -o json "${REPO_ROOT}/uv.lock")"
  while read -r original replacement; do
    sed "s/${original}/${replacement}/g" "${REPO_ROOT}/uv.lock" > uv.lock
    run bash "${GUARD}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *'Reassess'* ]]
  done < <(jq -r '
    .package[] | select(.name == "ecdsa") |
    "\(.version) \(.version).1",
    "\(.sdist.hash | sub("^sha256:"; "")) changed-sdist",
    "\(.wheels[].hash | sub("^sha256:"; "")) changed-wheel"
  ' <<< "${lock_json}")
}

@test "QA assessment rejects runtime dependencies in the root project" {
  sed 's/dependencies = \[\]/dependencies = ["ecdsa"]/' "${REPO_ROOT}/pyproject.toml" > pyproject.toml
  run bash "${GUARD}"
  [ "${status}" -eq 1 ]
}

@test "QA assessment rejects new consumers of ecdsa" {
  cat >> uv.lock << 'TOML'

[[package]]
name = "another-consumer"
version = "1.0.0"
dependencies = [{ name = "ecdsa" }]
TOML
  run bash "${GUARD}"
  [ "${status}" -eq 1 ]
}

@test "QA assessment rejects additional root Python manifests" {
  local manifest
  for manifest in requirements.txt Pipfile.lock poetry.lock pylock.toml setup.py setup.cfg; do
    touch "${manifest}"
    run bash "${GUARD}"
    [ "${status}" -eq 1 ]
    rm "${manifest}"
  done
}
