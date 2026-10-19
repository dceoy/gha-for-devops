#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/container-security.yml"
  BUILD_WORKFLOW="${REPO_ROOT}/.github/workflows/docker-build-and-push.yml"
  yq -r '.jobs.verify.steps[] | select(.name == "Validate verification policy") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/validate.sh"
  yq -r '.jobs.verify.steps[] | select(.id == "cosign") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/verify.sh"
  export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  export COSIGN_ARGS="${BATS_TEST_TMPDIR}/cosign-args"
  cat > "${BATS_TEST_TMPDIR}/bin/cosign" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${COSIGN_ARGS}"
exit "${COSIGN_EXIT_CODE:-0}"
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/cosign"
  DIGEST="sha256:$(printf 'a%.0s' {1..64})"
  IMAGE="ghcr.io/example/app@${DIGEST}"
  ISSUER=https://token.actions.githubusercontent.com
  REGEXP='^https://github\.com/dceoy/gha-for-devops/\.github/workflows/docker-build-and-push\.yml@(refs/.+|[0-9a-f]{40})$'
}

validate() {
  run env IMAGE_REF="$1" IDENTITY="$2" IDENTITY_REGEXP="$3" ISSUER="$4" bash -euo pipefail "${BATS_TEST_TMPDIR}/validate.sh"
}

@test "Verification workflow is read-only, pinned, and requires identity and issuer policy" {
  [ "$(yq -r '.jobs.verify.permissions | keys | join(",")' "${WORKFLOW}")" = contents ]
  grep -Fq 'sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6' "${WORKFLOW}"
  [ "$(yq -r '.on.workflow_call.inputs."image-refs-json".required' "${WORKFLOW}")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."verify-signatures".default' "${WORKFLOW}")" = true ]
  [ "$(yq -r '.on.workflow_call.inputs."certificate-oidc-issuer".default' "${WORKFLOW}")" = https://token.actions.githubusercontent.com ]
  for input in certificate-identity certificate-identity-regexp; do
    [ "$(INPUT="${input}" yq -r '.on.workflow_call.inputs[strenv(INPUT)].default // ""' "${WORKFLOW}")" = "" ]
  done
}

@test "Policy validation accepts digest-pinned images with one anchored identity" {
  validate "${IMAGE}" "" "${REGEXP}" "${ISSUER}"
  [ "${status}" -eq 0 ]
  validate "${IMAGE}" "https://github.com/o/r/.github/workflows/w.yml@refs/heads/main" "" "${ISSUER}"
  [ "${status}" -eq 0 ]
}

@test "Policy validation rejects tags, missing or ambiguous identity, and unanchored patterns" {
  validate "ghcr.io/example/app:latest" "" "${REGEXP}" "${ISSUER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"pinned by digest"* ]]
  validate "ghcr.io/example/app:1.0@${DIGEST}x" "" "${REGEXP}" "${ISSUER}"
  [ "${status}" -eq 1 ]
  validate "${IMAGE}" "" "" "${ISSUER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"identity is required"* ]]
  validate "${IMAGE}" "id" "${REGEXP}" "${ISSUER}"
  [ "${status}" -eq 1 ]
  validate "${IMAGE}" "" ".*" "${ISSUER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"anchored"* ]]
  validate "${IMAGE}" "" "${REGEXP}" "http://insecure.example"
  [ "${status}" -eq 1 ]
}

@test "Cosign is called with the exact identity and issuer policy" {
  run env IMAGE_REF="${IMAGE}" IDENTITY="https://github.com/o/r/.github/workflows/w.yml@refs/heads/main" IDENTITY_REGEXP="" ISSUER="${ISSUER}" bash -euo pipefail "${BATS_TEST_TMPDIR}/verify.sh"
  [ "${status}" -eq 0 ]
  mapfile -t args < "${COSIGN_ARGS}"
  [ "${args[0]}" = verify ]
  [[ " ${args[*]} " == *" --certificate-identity https://github.com/o/r/.github/workflows/w.yml@refs/heads/main "* ]]
  [[ " ${args[*]} " == *" --certificate-oidc-issuer ${ISSUER} "* ]]
  [[ " ${args[*]} " != *"--certificate-identity-regexp"* ]]
  [ "${args[-1]}" = "${IMAGE}" ]

  run env IMAGE_REF="${IMAGE}" IDENTITY="" IDENTITY_REGEXP="${REGEXP}" ISSUER="${ISSUER}" bash -euo pipefail "${BATS_TEST_TMPDIR}/verify.sh"
  [ "${status}" -eq 0 ]
  mapfile -t args < "${COSIGN_ARGS}"
  [[ " ${args[*]} " == *" --certificate-identity-regexp "* ]]
}

@test "Unsigned or incorrectly signed images fail the job" {
  run env COSIGN_EXIT_CODE=1 IMAGE_REF="${IMAGE}" IDENTITY="" IDENTITY_REGEXP="${REGEXP}" ISSUER="${ISSUER}" bash -euo pipefail "${BATS_TEST_TMPDIR}/verify.sh"
  [ "${status}" -eq 1 ]
}

@test "Build workflow keeps its reusable-workflow signer identity and digest-based verification" {
  # shellcheck disable=SC2016
  grep -Fq 'cosign sign --yes "{}@${DIGEST}"' "${BUILD_WORKFLOW}"
  grep -Fq 'https://github.com/dceoy/gha-for-devops/\\.github/workflows/docker-build-and-push\\.yml@(refs/.+|[0-9a-f]{40})' "${BUILD_WORKFLOW}"
  grep -Fq -- '--certificate-oidc-issuer https://token.actions.githubusercontent.com' "${BUILD_WORKFLOW}"
  # shellcheck disable=SC2016
  grep -Fq '"${tag}@${DIGEST}"' "${BUILD_WORKFLOW}"
  [ "$(yq -r '.on.workflow_call.inputs.cosign.default' "${BUILD_WORKFLOW}")" = false ]
  [ "$(yq -r '.on.workflow_call.inputs.provenance.default' "${BUILD_WORKFLOW}")" = false ]
  [ "$(yq -r '.jobs | to_entries | .[] | select(.value.steps != null) | .value.permissions."id-token"' "${BUILD_WORKFLOW}" | grep -c write)" -ge 1 ]
  # The documented policy values must match the build workflow's signer identity.
  grep -Fq 'docker-build-and-push\.yml@(refs/.+|[0-9a-f]{40})' "${WORKFLOW}"
}
