#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
}

@test "ECDSA assessment rejects version, source, and artifact changes" {
  local original replacement expected
  while read -r original replacement expected; do
    python3 - "${REPO_ROOT}/uv.lock" "${BATS_TEST_TMPDIR}/uv.lock" "${original}" "${replacement}" << 'PYTHON'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
assert sys.argv[3] in text
Path(sys.argv[2]).write_text(text.replace(sys.argv[3], sys.argv[4]))
PYTHON
    run bash "${REPO_ROOT}/scripts/check-qa-dependencies.sh" "${BATS_TEST_TMPDIR}/uv.lock"
    [ "${status}" -eq "${expected}" ]
  done << 'CASES'
3.3.26 3.3.26 0
3.3.26 3.3.27 1
0.19.2 0.19.3 1
https://pypi.org/simple https://unassessed.invalid/simple 1
3b4157e4a308ed72e86352b65331045d7b8172f7a4492741db85de6cf1a49b42 0000000000000000000000000000000000000000000000000000000000000000 1
840f5dc5e375c68f36c1a7a5b9caad28f95daa65185c9253c0c08dd952bb7399 0000000000000000000000000000000000000000000000000000000000000000 1
CASES
}

@test "ECDSA assessment rejects an additional dependency parent" {
  cp "${REPO_ROOT}/uv.lock" "${BATS_TEST_TMPDIR}/uv.lock"
  cat >> "${BATS_TEST_TMPDIR}/uv.lock" << 'TOML'
[[package]]
name = "other-tool"
version = "1.0.0"
dependencies = [{name = "ecdsa"}]
TOML
  run bash "${REPO_ROOT}/scripts/check-qa-dependencies.sh" "${BATS_TEST_TMPDIR}/uv.lock"
  [ "${status}" -eq 1 ]
}
