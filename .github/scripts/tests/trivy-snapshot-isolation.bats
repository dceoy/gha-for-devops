#!/usr/bin/env bats
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/trivy-scan.yml"
  yq -r '.jobs."trivy-prepare".steps[] | select(.id == "targets") | .run' "${WORKFLOW}" > "${BATS_TEST_TMPDIR}/prepare.sh"
}

@test "Concurrent Trivy callers isolate snapshots and download their own inventories" {
  [ "$(yq -r '.jobs."trivy-prepare".outputs."snapshot-namespace"' "${WORKFLOW}")" = '${{ steps.targets.outputs.snapshot-namespace }}' ]
  local upload download
  upload="$(yq -r '.jobs."trivy-scan".steps[] | select(.with.path == "${{ runner.temp }}/dependency-snapshot.json") | .with.name' "${WORKFLOW}")"
  download="$(yq -r '.jobs."trivy-submit".steps[] | select(.name == "Download dependency snapshot") | .with.name' "${WORKFLOW}")"
  [ "${upload}" = "${download}" ]

  local case_name scan_type prefix case_dir invocation pid_a pid_b namespace target_id name
  while read -r case_name scan_type prefix; do
    echo "case: ${case_name}"
    case_dir="${BATS_TEST_TMPDIR}/${case_name}"
    mkdir -p "${case_dir}/artifacts"
    # Identical inputs model separate caller jobs in the same workflow run.
    env SCAN_TYPE="${scan_type}" SCAN_REF=. IMAGE_REFS='["example/app:latest","example/worker:latest"]' \
      IMAGE_TARGETS='' CORRELATOR=stable GITHUB_OUTPUT="${case_dir}/a" bash -euo pipefail "${BATS_TEST_TMPDIR}/prepare.sh" &
    pid_a=$!
    env SCAN_TYPE="${scan_type}" SCAN_REF=. IMAGE_REFS='["example/app:latest","example/worker:latest"]' \
      IMAGE_TARGETS='' CORRELATOR=stable GITHUB_OUTPUT="${case_dir}/b" bash -euo pipefail "${BATS_TEST_TMPDIR}/prepare.sh" &
    pid_b=$!
    wait "${pid_a}"
    wait "${pid_b}"
    [ "$(sed -n 's/^snapshot-namespace=//p' "${case_dir}/a")" != "$(sed -n 's/^snapshot-namespace=//p' "${case_dir}/b")" ]

    for invocation in a b; do
      namespace="$(sed -n 's/^snapshot-namespace=//p' "${case_dir}/${invocation}")"
      [[ "${namespace}" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]
      while read -r target_id; do
        name="${upload//'${{ inputs.snapshot-artifact-prefix }}'/${prefix}}"
        name="${name//'${{ needs.trivy-prepare.outputs.snapshot-namespace }}'/${namespace}}"
        name="${name//'${{ matrix.id }}'/${target_id}}"
        [[ "${name}" != *'${{'* ]]
        [ ! -e "${case_dir}/artifacts/${name}" ]
        printf '%s\n' "${invocation}-${target_id}" > "${case_dir}/artifacts/${name}"
      done < <(sed -n 's/^targets=//p' "${case_dir}/${invocation}" | jq -r '.[].id')
    done
    # Resolve the actual download expression after all callers have uploaded.
    for invocation in a b; do
      namespace="$(sed -n 's/^snapshot-namespace=//p' "${case_dir}/${invocation}")"
      while read -r target_id; do
        name="${download//'${{ inputs.snapshot-artifact-prefix }}'/${prefix}}"
        name="${name//'${{ needs.trivy-prepare.outputs.snapshot-namespace }}'/${namespace}}"
        name="${name//'${{ matrix.id }}'/${target_id}}"
        [ "$(cat "${case_dir}/artifacts/${name}")" = "${invocation}-${target_id}" ]
      done < <(sed -n 's/^targets=//p' "${case_dir}/${invocation}" | jq -r '.[].id')
    done
  done << 'CASES'
Docker image docker-image
Bake image docker-bake
Multi-target image docker-image-app
Direct-image image trivy
Direct-filesystem filesystem trivy
CASES
}
