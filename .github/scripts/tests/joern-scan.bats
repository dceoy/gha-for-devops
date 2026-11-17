#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  local repo_root
  repo_root="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  local workflow="${repo_root}/.github/workflows/joern-scan.yml"
  prepare_script="$(yq -r '.jobs."joern-scan".steps[] | select(.name == "Prepare scan") | .run' "${workflow}")"
  execute_script="$(yq -r '.jobs."joern-scan".steps[] | select(.name == "Run joern-scan") | .run' "${workflow}")"
  evaluate_script="$(yq -r '.jobs."joern-scan".steps[] | select(.name == "Evaluate scan results") | .run' "${workflow}")"
  scan_dir="${BATS_TEST_TMPDIR}/checkout"
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  args_log="${BATS_TEST_TMPDIR}/joern-args"
  mkdir -p "${scan_dir}" "${bin_dir}"
  printf 'print("hello")\n' > "${scan_dir}/source.py"
  cat > "${bin_dir}/joern-scan" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${JOERN_ARGS_LOG}"
if [[ "${MOCK_QUERY_ERROR:-}" == true ]]; then
  echo 'Error executing query'
fi
if [[ "${MOCK_FINDING:-}" == true ]]; then
  echo 'Result: test finding'
fi
if [[ "${MOCK_INCOMPLETE:-}" != true ]]; then
  echo 'Run Joern to explore interactively'
fi
EOF
  chmod +x "${bin_dir}/joern-scan"
}

run_scan() {
  local github_env="${BATS_TEST_TMPDIR}/github-env"
  : > "${github_env}"
  run env \
    GITHUB_WORKSPACE="${scan_dir}" \
    GITHUB_ENV="${github_env}" \
    RUNNER_TEMP="${BATS_TEST_TMPDIR}" \
    SCAN_PATH="${scan_path:-${scan_dir}}" \
    SCAN_LANGUAGE="${scan_language:-}" \
    JOERN_SCAN_OPTIONS="${scan_options:-}" \
    FAIL_ON_FINDINGS="${fail_on_findings:-true}" \
    MOCK_QUERY_ERROR="${mock_query_error:-false}" \
    MOCK_FINDING="${mock_finding:-false}" \
    MOCK_INCOMPLETE="${mock_incomplete:-false}" \
    JOERN_ARGS_LOG="${args_log}" \
    PREPARE_SCRIPT="${prepare_script}" \
    EXECUTE_SCRIPT="${execute_script}" \
    EVALUATE_SCRIPT="${evaluate_script}" \
    PATH="${bin_dir}:${PATH}" \
    # shellcheck disable=SC2016 # Expanded by the child shell, not the caller.
    bash -euo pipefail -c '
      bash -euo pipefail -c "${PREPARE_SCRIPT}"
      # Emulate the GitHub Actions runner applying validated GITHUB_ENV values
      # between steps. Never source this file as executable shell code.
      while IFS="=" read -r name value; do
        case "${name}" in
          JOERN_SCAN_PATH | JOERN_LANGUAGE) export "${name}=${value}" ;;
          *) exit 1 ;;
        esac
      done < "${GITHUB_ENV}"
      bash -euo pipefail -c "${EXECUTE_SCRIPT}"
      bash -euo pipefail -c "${EVALUATE_SCRIPT}"
    '
}

@test "selects a real source frontend and ignores manifests" {
  printf '{}\n' > "${scan_dir}/package.json"
  run_scan
  [ "$status" -eq 0 ]
  grep -Fxq -- 'python' "${args_log}"
}

@test "rejects a directory with only manifests" {
  rm "${scan_dir}/source.py"
  printf '{}\n' > "${scan_dir}/package.json"
  run_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *'no recognized source files'* ]]
}

@test "rejects a Scala injection attempt in language" {
  scan_language='python"); println("PWNED") //'
  run_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *'not a recognized joern-scan frontend'* ]]
}

@test "rejects a Scala injection attempt in query filters" {
  scan_options='--tags all");println("PWNED")'
  run_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *'comma-separated identifiers'* ]]
}

@test "rejects multiline option injection" {
  scan_options=$'--store\n--dump'
  run_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *'must be a single line'* ]]
}

@test "allows a validated scan options list" {
  scan_options='--names sql-injection,flow --depth 2 --store'
  run_scan
  [ "$status" -eq 0 ]
  grep -Fxq -- 'sql-injection,flow' "${args_log}"
}

@test "rejects scan paths outside the checkout" {
  scan_path="${BATS_TEST_TMPDIR}"
  run_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *'inside the workspace'* ]]
}

@test "supports explicit frontend aliases" {
  rm "${scan_dir}/source.py"
  printf 'const x = 1;\n' > "${scan_dir}/source.ts"
  scan_language=jssrc
  run_scan
  [ "$status" -eq 0 ]
  grep -Fxq -- 'jssrc' "${args_log}"
}

@test "fails closed for an explicitly mismatched frontend" {
  scan_language=rust
  run_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *'no source files found for the selected Joern frontend'* ]]
}

@test "allows the binary-analysis ghidra frontend without a source extension" {
  rm "${scan_dir}/source.py"
  scan_language=ghidra
  run_scan
  [ "$status" -eq 0 ]
  grep -Fxq -- 'ghidra' "${args_log}"
}

@test "runs Joern from a digest-pinned official container" {
  local repo_root
  repo_root="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  image="$(yq -r '.jobs."joern-scan".container.image' "${repo_root}/.github/workflows/joern-scan.yml")"
  [[ "${image}" =~ ^ghcr\.io/joernio/joern:master@sha256:[a-f0-9]{64}$ ]]
  [[ "$(yq -r '.jobs."joern-scan".steps[] | select(.name == "Verify Joern query database") | .name' "${repo_root}/.github/workflows/joern-scan.yml")" == 'Verify Joern query database' ]]
}

@test "fails if Joern reports an incomplete scan" {
  mock_incomplete=true
  run_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *'did not report a completed scan'* ]]
}

@test "fails if Joern logs a query execution error" {
  mock_query_error=true
  run_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *'did not complete a full analysis'* ]]
}

@test "fails on findings when enabled" {
  mock_finding=true
  run_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *'reported 1 findings'* ]]
}

@test "warns on findings when failure is disabled" {
  mock_finding=true
  fail_on_findings=false
  run_scan
  [ "$status" -eq 0 ]
  [[ "$output" == *'::warning::joern-scan reported 1 findings'* ]]
}
