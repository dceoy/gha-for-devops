#!/usr/bin/env bash
set -euo pipefail

# Fail closed if the dependency graph no longer matches the ecdsa assessment.
python3 - "${1:-uv.lock}" << 'PYTHON'
import sys
import tomllib
from pathlib import Path

packages = tomllib.loads(Path(sys.argv[1]).read_text())["package"]
versions = {
    name: [p["version"] for p in packages if p["name"] == name]
    for name in ("checkov", "ecdsa")
}
parents = [
    p["name"]
    for p in packages
    if any(
        d["name"] == "ecdsa"
        for d in [
            *p.get("dependencies", []),
            *(d for deps in p.get("dev-dependencies", {}).values() for d in deps),
            *(d for deps in p.get("optional-dependencies", {}).values() for d in deps),
        ]
    )
]
if versions != {"checkov": ["3.3.26"], "ecdsa": ["0.19.2"]} or parents != ["checkov"]:
    sys.exit("Reassess the ecdsa advisory exception: locked versions or dependency path changed.")

# Bind the applicability assessment to the original PyPI artifacts, not a fork.
expected_artifacts = {
    "checkov": ['sha256:3b4157e4a308ed72e86352b65331045d7b8172f7a4492741db85de6cf1a49b42', 'sha256:90df926e9acf102452ba28bebe910738d76d84b5ce5974475fadae4bc319ddcf'],
    "ecdsa": ['sha256:62635b0ac1ca2e027f82122b5b81cb706edc38cd91c63dda28e4f3455a2bf930', 'sha256:840f5dc5e375c68f36c1a7a5b9caad28f95daa65185c9253c0c08dd952bb7399'],
}
for package in packages:
    if package["name"] not in expected_artifacts:
        continue
    hashes = sorted([
        package.get("sdist", {}).get("hash", ""),
        *(wheel.get("hash", "") for wheel in package.get("wheels", [])),
    ])
    if (package.get("source") != {"registry": "https://pypi.org/simple"}
            or hashes != expected_artifacts[package["name"]]):
        sys.exit("Reassess the ecdsa advisory exception: package source or artifacts changed.")
PYTHON
