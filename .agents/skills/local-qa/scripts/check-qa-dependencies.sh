#!/usr/bin/env bash
# Fail closed when the reviewed, verification-only ecdsa assessment changes.
set -euo pipefail

fail() {
  echo '::error::Reassess the root QA ecdsa advisory exception before using these dependencies.' >&2
  exit 1
}

# An additional root Python manifest would also inherit the root OSV exception.
for manifest in *requirements*.txt Pipfile Pipfile.lock poetry.lock pylock*.toml setup.py setup.cfg; do
  [[ ! -e "${manifest}" ]] || fail
done

yq -p toml -o json pyproject.toml | jq -e '
  .project.name == "local-qa" and
  .project.dependencies == [] and
  .tool.uv.package == false and
  (."dependency-groups".dev | index("checkov") != null)
' > /dev/null || fail

yq -p toml -o json uv.lock | jq -e '
  ([.package[] | select(any(.dependencies[]?; .name == "ecdsa")) | .name] == ["checkov"]) and
  ([.package[] | select(.name == "local-qa") | (.dependencies // [])] == [[]]) and
  ([.package[] | select(.name == "checkov")] | length == 1) and
  ([.package[] | select(.name == "ecdsa")] | length == 1) and
  all(.package[] | select(.name == "checkov" or .name == "ecdsa");
    .source == {registry: "https://pypi.org/simple"} and
    if .name == "checkov" then
      .version == "3.3.26" and
      ([.sdist.hash] + [.wheels[].hash] == [
        "sha256:90df926e9acf102452ba28bebe910738d76d84b5ce5974475fadae4bc319ddcf",
        "sha256:3b4157e4a308ed72e86352b65331045d7b8172f7a4492741db85de6cf1a49b42"
      ])
    else
      .version == "0.19.2" and
      ([.sdist.hash] + [.wheels[].hash] == [
        "sha256:62635b0ac1ca2e027f82122b5b81cb706edc38cd91c63dda28e4f3455a2bf930",
        "sha256:840f5dc5e375c68f36c1a7a5b9caad28f95daa65185c9253c0c08dd952bb7399"
      ])
    end
  )
' > /dev/null || fail

echo 'QA dependency assessment: ecdsa is used only for unaffected signature verification; exception expires 2026-11-17.'
