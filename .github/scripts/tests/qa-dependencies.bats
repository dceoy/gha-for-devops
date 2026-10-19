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

@test "QA assessment rejects changed reviewed versions and artifacts" {
  local original replacement
  while read -r original replacement; do
    sed "s/${original}/${replacement}/g" "${REPO_ROOT}/uv.lock" > uv.lock
    run bash "${GUARD}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *'Reassess'* ]]
  done << 'CASES'
3.3.28 3.3.29
0.19.2 0.19.3
895094b92ac0cce92660485409919a11ef05bfa94913b0b2b29f1ff2d9e79cd2 changed-wheel
df5cc64db4c8626da5abf3b67e6bbd3c70d9425ad2b2f28391e61e02a483a34e changed-sdist
840f5dc5e375c68f36c1a7a5b9caad28f95daa65185c9253c0c08dd952bb7399 changed-wheel
62635b0ac1ca2e027f82122b5b81cb706edc38cd91c63dda28e4f3455a2bf930 changed-sdist
CASES
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
