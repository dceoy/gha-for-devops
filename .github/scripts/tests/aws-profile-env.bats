#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  TEST_DIR="$(mktemp -d)"
}
teardown() { rm -rf "${TEST_DIR}"; }

run_profile() {
  local workflow="$1"
  local entries="$2"
  yq -r '.jobs[] | select(has("steps")) | .steps[] | select(.id == "aws-profile-env") | .run' \
    "${REPO_ROOT}/.github/workflows/${workflow}.yml" > "${TEST_DIR}/parse.sh"
  [[ -s "${TEST_DIR}/parse.sh" ]] || return 1
  printf '%s\n' "${entries}" > "${TEST_DIR}/profile.env"
  : > "${TEST_DIR}/output"
  run env AWS_PROFILE_ENV_FILE="${TEST_DIR}/profile.env" \
    GITHUB_OUTPUT="${TEST_DIR}/output" bash -euo pipefail "${TEST_DIR}/parse.sh"
}

@test "only approved AWS values become step outputs" {
  for workflow in aws-codebuild-run docker-pull-from-aws terraform-deploy-to-aws terragrunt-aws-switch-resources; do
    run_profile "${workflow}" $'# comment\nROLE_ARN=arn:aws:iam::123456789012:role/path/MyRole\nREGION=us-east-1\nEXTRA=discarded'
    [ "${status}" -eq 0 ]
    [ "$(cat "${TEST_DIR}/output")" = $'ROLE_ARN=arn:aws:iam::123456789012:role/path/MyRole\nREGION=us-east-1' ]
  done
}

@test "CodeBuild project name is output only in CodeBuild" {
  for workflow in aws-codebuild-run docker-pull-from-aws terraform-deploy-to-aws terragrunt-aws-switch-resources; do
    run_profile "${workflow}" 'AWS_CODEBUILD_PROJECT_NAME=build-project'
    [ "${status}" -eq 0 ]
    if [ "${workflow}" = aws-codebuild-run ]; then
      [ "$(cat "${TEST_DIR}/output")" = 'AWS_CODEBUILD_PROJECT_NAME=build-project' ]
    else
      [ ! -s "${TEST_DIR}/output" ]
    fi
  done
}

@test "invalid role ARNs and output injection fail closed" {
  for workflow in aws-codebuild-run docker-pull-from-aws terraform-deploy-to-aws terragrunt-aws-switch-resources; do
    run_profile "${workflow}" 'ROLE_ARN=arn:aws:iam::bad:role/bad'
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'Invalid ROLE_ARN'* ]]
    run_profile "${workflow}" $'ROLE_ARN=arn:aws:iam::123456789012:role/valid\nROLE_ARN<<EOF\nbad\nEOF'
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'Invalid AWS profile entry'* ]]
    ! grep -q '^ROLE_ARN<<' "${TEST_DIR}/output"
  done
}

@test "invalid region and duplicate entries are rejected" {
  for workflow in aws-codebuild-run docker-pull-from-aws terraform-deploy-to-aws terragrunt-aws-switch-resources; do
    run_profile "${workflow}" 'REGION=us-east-1 extra'
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'Invalid REGION'* ]]
    run_profile "${workflow}" $'ROLE_ARN=arn:aws:iam::123456789012:role/one\nROLE_ARN=arn:aws:iam::123456789012:role/two'
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'Duplicate ROLE_ARN'* ]]
  done
}

@test "alternative AWS partitions and CRLF are accepted" {
  run_profile terraform-deploy-to-aws $'ROLE_ARN=arn:aws-us-gov:iam::123456789012:role/team/build\r\nREGION=us-gov-west-1\r'
  [ "${status}" -eq 0 ]
  [ "$(cat "${TEST_DIR}/output")" = $'ROLE_ARN=arn:aws-us-gov:iam::123456789012:role/team/build\nREGION=us-gov-west-1' ]
  run_profile aws-codebuild-run $'ROLE_ARN=arn:aws-cn:iam::123456789012:role/build\nREGION=cn-north-1'
  [ "${status}" -eq 0 ]
}
