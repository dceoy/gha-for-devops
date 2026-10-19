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
      .version == "3.3.28" and
      ([.sdist.hash] + [.wheels[].hash] == [
        "sha256:df5cc64db4c8626da5abf3b67e6bbd3c70d9425ad2b2f28391e61e02a483a34e",
        "sha256:895094b92ac0cce92660485409919a11ef05bfa94913b0b2b29f1ff2d9e79cd2"
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
