#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  BAKE_WORKFLOW="${REPO_ROOT}/.github/workflows/docker-buildx-bake.yml"
  TRIVY_WORKFLOW="${REPO_ROOT}/.github/workflows/trivy-scan.yml"
  MATRIX_SCRIPT="$(yq -r '.jobs."docker-buildx-bake".steps[] | select(.id == "dependency-snapshot-matrix") | .run' "${BAKE_WORKFLOW}")"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/matrix-output"
}

generate_matrix() {
  : > "${GITHUB_OUTPUT}"
  run env BAKE_OUTPUT_METADATA_JSON="${1}" bash -euo pipefail -c "${MATRIX_SCRIPT}"
  [ "${status}" -eq 0 ]
  MATRIX="$(sed -n 's/^matrix=//p' "${GITHUB_OUTPUT}")"
  [ -n "${MATRIX}" ]
}

@test "different images with the same Bake target get distinct snapshot correlators" {
  generate_matrix '{"default":{"image.name":"ghcr.io/example/alpha:v1","containerimage.digest":"sha256:aaaa"}}'
  local alpha
  alpha="$(jq -r '.[0].correlator' <<< "${MATRIX}")"

  generate_matrix '{"default":{"image.name":"ghcr.io/example/beta:v1","containerimage.digest":"sha256:bbbb"}}'
  local beta
  beta="$(jq -r '.[0].correlator' <<< "${MATRIX}")"

  [ "${alpha}" != "${beta}" ]
  [ "${alpha}" = "docker-bake-default-ghcr.io/example/alpha" ]
  [ "${beta}" = "docker-bake-default-ghcr.io/example/beta" ]
}

@test "changing image tags and digests preserves the inventory correlator" {
  generate_matrix '{"default":{"image.name":"ghcr.io/example/alpha:v1,ghcr.io/example/alpha:latest","containerimage.digest":"sha256:aaaa"}}'
  local first
  first="$(jq -r '.[0].correlator' <<< "${MATRIX}")"

  generate_matrix '{"default":{"image.name":"ghcr.io/example/alpha:v2","containerimage.digest":"sha256:bbbb"}}'
  [ "$(jq -r '.[0].correlator' <<< "${MATRIX}")" = "${first}" ]
  [ "$(jq -r '.[0].image_ref' <<< "${MATRIX}")" = "ghcr.io/example/alpha:v2@sha256:bbbb" ]
}

@test "multiple targets and a registry port keep distinct image identities" {
  generate_matrix '{"api":{"image.name":"registry.example:5000/team/service:prod","containerimage.digest":"sha256:aaaa"},"worker":{"image.name":"registry.example:5000/team/service:prod","containerimage.digest":"sha256:bbbb"}}'
  jq -e 'length == 2 and (.[0].correlator != .[1].correlator)' <<< "${MATRIX}"
  jq -e '[.[].correlator] | all(contains("registry.example:5000/team/service"))' <<< "${MATRIX}"
}

@test "a Bake submission without a pushed image digest fails explicitly" {
  run env BAKE_OUTPUT_METADATA_JSON='{"default":{"image.name":"ghcr.io/example/alpha:v1"}}' \
    bash -euo pipefail -c "${MATRIX_SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"No pushed images with digests"* ]]
}

@test "Bake feeds pinned targets to one Trivy scan that publishes from a separate privileged job" {
  [ "$(yq -r '.jobs."docker-bake-postbuild-scan".uses' "$BAKE_WORKFLOW")" = '$/.github/workflows/trivy-scan.yml' ]
  [ "$(yq -r '.jobs."docker-bake-postbuild-scan".permissions.contents' "$BAKE_WORKFLOW")" = write ]
  [ "$(yq -r '.jobs."docker-bake-postbuild-scan".permissions.packages' "$BAKE_WORKFLOW")" = read ]
  [ "$(yq -r '.jobs."docker-bake-postbuild-scan".with."image-targets-json"' "$BAKE_WORKFLOW" | grep -c dependency-snapshot-matrix)" -gt 0 ]
  [ "$(yq -r '.jobs."trivy-scan".permissions.contents' "$TRIVY_WORKFLOW")" = read ]
  [ "$(yq -r '.jobs."trivy-submit".permissions.contents' "$TRIVY_WORKFLOW")" = null ]
  [ "$(yq -r '.jobs."docker-postbuild-scan".uses' "$REPO_ROOT/.github/workflows/docker-build-and-push.yml")" = '$/.github/workflows/trivy-scan.yml' ]
  run ! grep -Fq 'dependency-submission.yml' "$BAKE_WORKFLOW"
}
