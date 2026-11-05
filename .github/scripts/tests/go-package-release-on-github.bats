#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/go-package-release-on-github.yml"
  TEST_TEMP="$(mktemp -d)"
  PROJECT="${TEST_TEMP}/project"
  DIST_DIR="${TEST_TEMP}/dist"
  mkdir -p "${PROJECT}/cmd/hello" "${PROJECT}/internal/version"
  cat > "${PROJECT}/go.mod" << 'EOF'
module example.com/hello

go 1.22
EOF
  cat > "${PROJECT}/internal/version/version.go" << 'EOF'
package version

var Version = "dev"
EOF
  cat > "${PROJECT}/cmd/hello/main.go" << 'EOF'
package main

import (
	"fmt"

	"example.com/hello/internal/version"
)

func main() {
	fmt.Println(version.Version)
}
EOF
}

teardown() {
  rm -rf "${TEST_TEMP}"
}

run_step() {
  local job="$1"
  local step_name="$2"
  shift 2
  local step_script="${TEST_TEMP}/${step_name// /-}.sh"

  yq -r ".jobs.\"${job}\".steps[] | select(.name == \"${step_name}\") | .run" "${WORKFLOW}" > "${step_script}"
  # shellcheck disable=SC2016
  run env "$@" bash -c 'cd "$1" && exec bash -euo pipefail "$2"' _ "${PROJECT}" "${step_script}"
}

run_build() {
  run_step go-release-build 'Build binaries and checksums' \
    RELEASE_TAG=v1.2.3 \
    GO_MAIN_PACKAGE=cmd/hello \
    GO_BINARY_NAME= \
    GO_VERSION_VARIABLE= \
    GO_CGO_ENABLED=0 \
    GO_LDFLAGS='-s -w' \
    CHECKSUM_FILE_NAME=SHA256SUMS \
    DIST_DIR="${DIST_DIR}" \
    "$@"
}

@test 'release job delegates to github-release and gates the build on a release tag' {
  [ "$(yq -r '.jobs."github-release".uses' "${WORKFLOW}")" = '$/.github/workflows/github-release.yml' ]
  [ "$(yq -r '.jobs."github-release".permissions.contents' "${WORKFLOW}")" = write ]
  [ "$(yq -r '.jobs."go-release-build".if' "${WORKFLOW}")" = "needs.github-release.outputs.release-tag != ''" ]
  [ "$(yq -r '.jobs."go-release-build".permissions.contents' "${WORKFLOW}")" = read ]
  [ "$(yq -r '.jobs."go-release-upload".permissions.contents' "${WORKFLOW}")" = write ]
  [ "$(yq -r '.jobs."go-release-build".steps[] | select(.name == "Set up Go") | .with.cache' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.outputs."release-tag".value' "${WORKFLOW}")" = "\${{ jobs.github-release.outputs.release-tag }}" ]
}

@test 'build step cross-compiles binaries with the release version and checksums' {
  run_build GO_TARGETS=$'linux/amd64 windows/amd64\ndarwin/arm64' \
    GO_VERSION_VARIABLE=example.com/hello/internal/version.Version
  [ "${status}" -eq 0 ]
  [ -f "${DIST_DIR}/hello_v1.2.3_linux_amd64" ]
  [ -f "${DIST_DIR}/hello_v1.2.3_windows_amd64.exe" ]
  [ -f "${DIST_DIR}/hello_v1.2.3_darwin_arm64" ]
  [ "$(wc -l < "${DIST_DIR}/SHA256SUMS")" -eq 3 ]
  (cd "${DIST_DIR}" && sha256sum --check --quiet SHA256SUMS)
  if [[ "$(go env GOOS)/$(go env GOARCH)" == linux/amd64 ]]; then
    [ "$("${DIST_DIR}/hello_v1.2.3_linux_amd64")" = v1.2.3 ]
  fi
}

@test 'build step honors an explicit binary name' {
  run_build GO_TARGETS=linux/arm64 GO_BINARY_NAME=hello-cli
  [ "${status}" -eq 0 ]
  [ -f "${DIST_DIR}/hello-cli_v1.2.3_linux_arm64" ]
}

@test 'build step rejects unsupported or duplicate targets' {
  run_build GO_TARGETS=plan10/amd64
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Unsupported build target: plan10/amd64'* ]]

  run_build GO_TARGETS='linux/amd64 linux/amd64'
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Duplicate build target: linux/amd64'* ]]

  run_build GO_TARGETS=' '
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'targets must contain at least one'* ]]
}

@test 'build step rejects a non-main package' {
  run_build GO_TARGETS=linux/amd64 GO_MAIN_PACKAGE=internal/version
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'main-package is not a main package'* ]]
}

@test 'input validation rejects unsafe values' {
  local -a valid=(
    RELEASE_TAG=v1.2.3
    GO_WORKING_DIRECTORY=.
    GO_MAIN_PACKAGE=cmd/hello
    GO_BINARY_NAME=
    GO_VERSION_VARIABLE=example.com/hello/internal/version.Version
    CHECKSUM_FILE_NAME=SHA256SUMS
  )
  run_step go-release-build 'Validate inputs' "${valid[@]}"
  [ "${status}" -eq 0 ]

  run_step go-release-build 'Validate inputs' "${valid[@]}" 'RELEASE_TAG=v1 2'
  [ "${status}" -ne 0 ]

  run_step go-release-build 'Validate inputs' "${valid[@]}" GO_MAIN_PACKAGE=../evil
  [ "${status}" -ne 0 ]

  run_step go-release-build 'Validate inputs' "${valid[@]}" 'GO_BINARY_NAME=a/b'
  [ "${status}" -ne 0 ]

  run_step go-release-build 'Validate inputs' "${valid[@]}" 'GO_VERSION_VARIABLE=Version -X x.y=z'
  [ "${status}" -ne 0 ]

  run_step go-release-build 'Validate inputs' "${valid[@]}" GO_WORKING_DIRECTORY=cmd
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'go.mod not found'* ]]
}

@test 'release stays a draft until binaries are attached' {
  [ "$(yq -r '.jobs."github-release".with.draft' "${WORKFLOW}")" = true ]
  [ "$(yq -r '.jobs."go-release-upload".steps[].name' "${WORKFLOW}" | tail -n 2 | paste -sd, -)" = 'Attach binaries and checksums to the release,Publish the release' ]
  [[ "$(yq -r '.jobs."go-release-upload".steps[] | select(.name == "Publish the release") | .run' "${WORKFLOW}")" == *'--draft=false'* ]]
  [ "$(yq -r '.on.workflow_call.inputs | has("artifact-name")' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.jobs."go-release-build".steps[] | select(.name == "Stage release assets") | .with.name' "${WORKFLOW}")" = go-release-assets ]
  [ "$(yq -r '.jobs."go-release-upload".steps[] | select(.name == "Download release assets") | .with.name' "${WORKFLOW}")" = go-release-assets ]
}

@test 'build step evaluates main package constraints per target' {
  rm "${PROJECT}/cmd/hello/main.go"
  cat > "${PROJECT}/cmd/hello/main_windows.go" << 'GO'
package main

func main() {}
GO
  run_build GO_TARGETS=windows/amd64
  [ "${status}" -eq 0 ]
  [ -f "${DIST_DIR}/hello_v1.2.3_windows_amd64.exe" ]
}

@test 'build step rejects cgo cross-compilation targets' {
  local foreign=linux/arm64
  [[ "$(go env GOHOSTOS)/$(go env GOHOSTARCH)" == linux/arm64 ]] && foreign=linux/amd64
  run_build GO_TARGETS="${foreign}" GO_CGO_ENABLED=1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"cgo-enabled builds support only the runner's native target"* ]]
}
