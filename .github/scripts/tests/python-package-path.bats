#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOWS="${REPO_ROOT}/.github/workflows"
}

@test "Python package install steps validate package-path without extra steps" {
  local workflow step guard path
  for workflow in python-package-test python-package-format-and-pr python-package-lint-and-scan python-package-mkdocs-gh-deploy; do
    for step in "Install packages using uv" "Install packages using uv pip"; do
      guard="$(yq -r ".jobs.*.steps[] | select(.name == \"${step}\") | .run" "${WORKFLOWS}/${workflow}.yml" | head -n 4)"
      [[ "${guard}" == *"PACKAGE_PATH"* ]]
      for path in . service/app "service with spaces" "パッケージ"; do
        run env PACKAGE_PATH="${path}" bash -euo pipefail -c "${guard}"
        [ "${status}" -eq 0 ]
      done
      for path in /root ../escape service/../other 'service\..\other' 'C:\windows' 'C:relative' '\\server' 'service\app' 'service/[1]' 'service/*' 'service/?' 'service/{a,b}' '!app' 'app@(other)'; do
        run env PACKAGE_PATH="${path}" bash -euo pipefail -c "${guard}"
        [ "${status}" -ne 0 ]
        [[ "${output}" == *"package-path must be relative"* ]]
      done
    done
  done
}

@test "Python package release checks the same invalid paths" {
  local script project path
  script="$(yq -r '.jobs."python-release-build".steps[] | select(.id == "read-project-name") | .run' "${WORKFLOWS}/python-package-release-on-pypi-and-github.yml")"
  project="${BATS_TEST_TMPDIR}/project"
  mkdir -p "${project}"
  printf '[project]\nname = "sample"\n' > "${project}/pyproject.toml"
  for path in . service/app; do
    run bash -c 'cd "$1" && env PACKAGE_PATH="$2" GITHUB_OUTPUT="$3" python3 -c "$4"' _ "${project}" "${path}" "${project}/output" "${script}"
    [ "${status}" -eq 0 ]
  done
  for path in ../escape 'service\..\other' 'C:\windows' 'C:relative' 'service\app' 'service/[1]' 'service/*' 'app@(other)'; do
    run bash -c 'cd "$1" && env PACKAGE_PATH="$2" GITHUB_OUTPUT="$3" python3 -c "$4"' _ "${project}" "${path}" "${project}/output" "${script}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"package-path must be relative"* ]]
  done
}
