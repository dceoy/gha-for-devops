#!/usr/bin/env bats

setup() {
  export PIN_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/github-action-release-pins.yml"
  export MAJOR_TAG_WORKFLOW="${BATS_TEST_DIRNAME}/../../workflows/github-major-version-tag.yml"
  export PIN_SCRIPT="${BATS_TEST_TMPDIR}/update-pins.sh"
  yq -r '.jobs."release-pins".steps[] | select(.name == "Update pinned references") | .run' "${PIN_WORKFLOW}" > "${PIN_SCRIPT}"
}

make_fixture() {
  local repo="$1"
  local input="$2"
  local directory="${BATS_TEST_TMPDIR}/${repo}"
  mkdir -p "${directory}/docs"
  cat > "${directory}/README.md" <<EOF
- uses: dceoy/${repo}@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  # v0.0.1
- uses: actions/checkout@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  # v0.0.1
EOF
  cat > "${directory}/action.yml" <<EOF
  ${input}:
    required: false
    description: Pinned pr-loop commit
    default: cccccccccccccccccccccccccccccccccccccccc  # v1.0.0
EOF
  cat > "${directory}/docs/reusable-workflows.md" <<EOF
- uses: dceoy/${repo}/.github/workflows/${repo}-bot.yml@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  # v0.0.1
- uses: dceoy/${repo}/.github/workflows/${repo}-review.yml@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  # v0.0.1
EOF
  cd "${directory}" || exit 1
  export GITHUB_REPOSITORY="dceoy/${repo}"
  export PR_LOOP_REF_INPUT="${input}"
  export RELEASE_TAG="v1.2.3"
  export RELEASE_SHA="dddddddddddddddddddddddddddddddddddddddd"
  export CHECKOUT_TAG="v7.0.1"
  export CHECKOUT_SHA="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  export PR_LOOP_TAG="v2.0.1"
  export PR_LOOP_SHA="ffffffffffffffffffffffffffffffffffffffff"
}

@test 'reusable workflow keeps least-privilege PR permissions and latest-release guard' {
  [ "$(yq -r '.jobs."release-pins".permissions.contents' "${PIN_WORKFLOW}")" = write ]
  [ "$(yq -r '.jobs."release-pins".permissions."pull-requests"' "${PIN_WORKFLOW}")" = write ]
  [ "$(yq -r '.permissions.contents' "${PIN_WORKFLOW}")" = read ]
  [ "$(yq -r '.on.workflow_call.inputs."update-reusable-workflow-docs".default' "${PIN_WORKFLOW}")" = false ]
  yq -r '.jobs."release-pins".steps[] | select(.id == "release") | .run' "${PIN_WORKFLOW}" \
    | grep -Fq 'skipping stale pin updates'
}

@test 'release pin update handles pi-action and opencode-action differences' {
  local repo input
  for repo in pi-action opencode-action; do
    input=pr-loop-ref
    [ "${repo}" != opencode-action ] || input=pr-review-ref
    make_fixture "${repo}" "${input}"
    export UPDATE_WORKFLOW_DOCS=false
    [ "${repo}" != opencode-action ] || UPDATE_WORKFLOW_DOCS=true
    run bash -euo pipefail "${PIN_SCRIPT}"
    [ "${status}" -eq 0 ]
    grep -Fq "dceoy/${repo}@${RELEASE_SHA}  # ${RELEASE_TAG}" README.md
    grep -Fq "actions/checkout${CHECKOUT_SHA}  # ${CHECKOUT_TAG}" README.md
    grep -Fq "default: ${PR_LOOP_SHA}  # ${PR_LOOP_TAG}" action.yml
    if [ "${repo}" = opencode-action ]; then
      [ "$(grep -Ec "opencode-action/\\.github/workflows/.*${RELEASE_SHA}" docs/reusable-workflows.md)" -eq 2 ]
    fi
    run bash -euo pipefail "${PIN_SCRIPT}"
    [ "${status}" -eq 0 ]
  done
}

@test 'release pin updates fail closed if required docs references are missing' {
  make_fixture opencode-action pr-review-ref
  export UPDATE_WORKFLOW_DOCS=true
  sed -i '/opencode-action-review.yml/d' docs/reusable-workflows.md
  run bash -euo pipefail "${PIN_SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'expected two self-referencing pins'* ]]
}

@test 'major-tag workflow accepts an explicit tag but rejects stale releases' {
  [ "$(yq -r '.on.workflow_call.inputs."tag-name".type' "${MAJOR_TAG_WORKFLOW}")" = string ]
  [ "$(yq -r '.on.workflow_dispatch.inputs."tag-name".type' "${MAJOR_TAG_WORKFLOW}")" = string ]
  yq -r '.jobs."github-major-version-tag".steps[0].run' "${MAJOR_TAG_WORKFLOW}" \
    | grep -Fq 'Refusing to move floating version tags to non-latest release'
}
