#!/usr/bin/env bash
#
# Regenerate README.md from README.md.tmpl and reusable workflows in
# .github/workflows using yq, gomplate, and Prettier.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

WORKFLOWS_JSON="$(mktemp)"
trap 'rm -f "${WORKFLOWS_JSON}"' EXIT

yq eval-all --output-format=json '
  [
    select(.name and ((.on == "workflow_call") or (.on | has("workflow_call"))))
    | {"file": (filename | sub("^.*/"; "")), "name": .name}
  ]
  | sort_by(.file)
' .github/workflows/*.yml > "${WORKFLOWS_JSON}"

if [[ "$(yq eval 'tag' "${WORKFLOWS_JSON}")" != '!!seq' ]]; then
  echo "::error::generated workflow metadata in ${WORKFLOWS_JSON} is not a JSON array" >&2
  exit 1
fi
if [[ "$(yq eval 'length' "${WORKFLOWS_JSON}")" -eq 0 ]]; then
  echo "::error::no reusable (workflow_call) workflows found under .github/workflows; refusing to overwrite README.md" >&2
  exit 1
fi

gomplate \
  --datasource "workflows=file://${WORKFLOWS_JSON}?type=application/json" \
  --file README.md.tmpl --out README.md
prettier --parser markdown --write README.md.tmpl
prettier --write README.md
