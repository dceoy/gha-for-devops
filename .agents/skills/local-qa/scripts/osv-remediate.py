#!/usr/bin/env python3
"""Attempt bounded, lockfile-only remediation for OSV findings in uv and pnpm."""

import json
import re
import subprocess
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

MAX_PACKAGES = 20
PYPI_NAME = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*\Z")
NPM_NAME = re.compile(r"(?:@[a-zA-Z0-9][a-zA-Z0-9_.-]*/)?[a-zA-Z0-9][a-zA-Z0-9_.-]*\Z")
PNPM_ENTRY = re.compile(r"^  ['\"]?(.+?)@(\d+\.\d+\.\d+(?:[-+][\w.-]+)?)(?:\([^:]*\))?['\"]?:\s*$", re.M)
VERSION = re.compile(r"^v?(\d+(?:\.\d+)*)$")


def versions(lockfile: Path) -> dict[str, set[str]]:
    """Read resolved versions without installing or invoking a package manager."""
    result: dict[str, set[str]] = defaultdict(set)
    if lockfile.name == "uv.lock":
        for package in tomllib.loads(lockfile.read_text()).get("package", []):
            result[package["name"].lower()].add(package["version"])
    else:
        for match in PNPM_ENTRY.finditer(lockfile.read_text()):
            result[match.group(1)].add(match.group(2))
    return result


def release(version: str) -> tuple[int, ...] | None:
    """Parse ordinary PEP 440 release segments; decline unsupported pre/post releases."""
    match = VERSION.fullmatch(version)
    if not match:
        return None
    numbers = tuple(map(int, match.group(1).split(".")))
    return numbers + (0,) * max(0, 3 - len(numbers))


def safe_upgrade(before: dict, after: dict) -> bool:
    """Reject downgrades or major jumps, including versions without three segments."""
    if not before or not after:
        return False
    for name, new_versions in after.items():
        old_versions = before.get(name)
        if not old_versions or old_versions == new_versions:
            continue  # New transitive dependencies are checked by the OSV rescan.
        old = [release(version) for version in old_versions]
        new = [release(version) for version in new_versions]
        if None in old or None in new:
            return False
        old_releases = [value for value in old if value is not None]
        new_releases = [value for value in new if value is not None]
        if any(
            not any(a[0] == b[0] and a >= b for a in new_releases)
            for b in old_releases
        ):
            return False
        if any(
            not any(a[0] == b[0] and a >= b for b in old_releases)
            for a in new_releases
        ):
            return False
    return True


def main(report: Path) -> None:
    root = Path.cwd().resolve()
    try:
        results = json.loads(report.read_text()).get("results", [])
    except (OSError, ValueError) as error:
        print(f"OSV auto-remediation skipped: invalid report: {error}", file=sys.stderr)
        return

    candidates: dict[Path, set[str]] = defaultdict(set)
    for result in results:
        source = result.get("source", {}).get("path", "")
        if not source:
            continue
        lockfile = Path(source).resolve()
        if not lockfile.is_relative_to(root):
            continue
        if lockfile.name == "uv.lock":
            ecosystem, name_pattern = "PyPI", PYPI_NAME
        elif lockfile.name == "pnpm-lock.yaml":
            ecosystem, name_pattern = "npm", NPM_NAME
        else:
            continue
        for finding in result.get("packages", []):
            package = finding.get("package", {})
            name = package.get("name", "")
            if (
                finding.get("vulnerabilities")
                and package.get("ecosystem") == ecosystem
                and name_pattern.fullmatch(name)
            ):
                candidates[lockfile].add(name)

    for lockfile, packages in sorted(candidates.items()):
        relative = lockfile.relative_to(root).as_posix()
        if len(packages) > MAX_PACKAGES:
            print(f"OSV auto-remediation skipped {relative}: too many packages ({len(packages)})")
            continue
        tracked = subprocess.run(
            ["git", "ls-files", "--error-unmatch", "--", relative],
            cwd=root,
            capture_output=True,
            check=False,
        )
        dirty = subprocess.run(
            ["git", "status", "--porcelain", "--", relative],
            cwd=root,
            capture_output=True,
            check=False,
        )
        if tracked.returncode or dirty.returncode or dirty.stdout:
            print(f"OSV auto-remediation skipped {relative}: untracked or modified lockfile")
            continue

        original = lockfile.read_bytes()
        try:
            previous = versions(lockfile)
            if lockfile.name == "uv.lock":
                command = [
                    "uv",
                    "lock",
                    *(f"--upgrade-package={name}" for name in sorted(packages)),
                ]
            else:
                command = [
                    "pnpm",
                    "update",
                    "--lockfile-only",
                    "--no-save",
                    "--ignore-scripts",
                    *sorted(packages),
                ]
            print(f"OSV auto-remediation: {relative} ({', '.join(sorted(packages))})", flush=True)
            execution = subprocess.run(command, cwd=lockfile.parent, check=False)
            if execution.returncode or not safe_upgrade(previous, versions(lockfile)):
                print(f"OSV auto-remediation rejected {relative}: update failed or unsafe version change")
                lockfile.write_bytes(original)
            elif lockfile.read_bytes() == original:
                print(f"OSV auto-remediation: no compatible update for {relative}")
            else:
                print(f"OSV auto-remediation updated {relative}; rescanning dependencies")
        except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
            lockfile.write_bytes(original)
            print(f"OSV auto-remediation failed for {relative}: {error}", file=sys.stderr)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
