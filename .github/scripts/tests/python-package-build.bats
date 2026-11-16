#!/usr/bin/env bats

setup() {
  export BUILD_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/python-package-build.yml"
  export LEGACY_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/python-package-release-on-pypi-and-github.yml"
  export PREPARE_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/python-package-release-prepare.yml"
}

@test 'distribution build stays read-only and never signs or publishes' {
  [ "$(yq -r '.permissions.contents' "${BUILD_WORKFLOW}")" = read ]
  [ "$(yq -r '.jobs | keys | join(",")' "${BUILD_WORKFLOW}")" = python-package-build ]
  [ "$(yq -r '.on.workflow_call.outputs."project-name".value' "${BUILD_WORKFLOW}")" = "\${{ jobs.python-package-build.outputs.project-name }}" ]
  [ "$(yq -r '.on.workflow_call.outputs."distribution-artifact-name".value' "${BUILD_WORKFLOW}")" = "\${{ inputs.distribution-artifact-name }}" ]
  [ "$(yq -r '.jobs."python-package-build".steps[] | select(.name == "Store the distribution packages") | .with.name' "${BUILD_WORKFLOW}")" = "\${{ inputs.distribution-artifact-name }}" ]
  [ "$(yq -r '.jobs."python-package-build".steps | length' "${BUILD_WORKFLOW}")" -eq 6 ]
}

@test 'legacy release wrapper forwards build inputs without changing release jobs' {
  [ "$(yq -r '.jobs."python-release-build".uses' "${LEGACY_WORKFLOW}")" = '$/.github/workflows/python-package-build.yml' ]
  [ "$(yq -r '.jobs."python-release-build".permissions.contents' "${LEGACY_WORKFLOW}")" = read ]
  [ "$(yq -r '.on.workflow_call.outputs."project-name".value' "${LEGACY_WORKFLOW}")" = "\${{ jobs.python-release-build.outputs.project-name }}" ]
  [ "$(yq -r '.jobs."python-release-build".with."artifact-overwrite"' "${LEGACY_WORKFLOW}")" = "\${{ inputs.artifact-overwrite }}" ]
  [ "$(yq -r '.jobs."python-release-build".with."requirements-txt"' "${LEGACY_WORKFLOW}")" = "\${{ inputs.requirements-txt }}" ]
  [ "$(yq -r '.jobs."python-release-testpypi".needs[0]' "${LEGACY_WORKFLOW}")" = python-release-build ]
  [ "$(yq -r '.jobs."python-release-github".needs[0]' "${LEGACY_WORKFLOW}")" = python-release-build ]
  [ "$(yq -r '.jobs."python-release-pypi".needs | index("python-release-build") != null' "${LEGACY_WORKFLOW}")" = true ]
}

@test 'guarded release preparation calls build without publishing permissions' {
  [ "$(yq -r '.jobs.build.uses' "${PREPARE_WORKFLOW}")" = '$/.github/workflows/python-package-build.yml' ]
  [ "$(yq -r '.jobs.build.permissions.contents' "${PREPARE_WORKFLOW}")" = read ]
  [ "$(yq -r '.jobs.build.permissions."id-token" // "none"' "${PREPARE_WORKFLOW}")" = none ]
}
