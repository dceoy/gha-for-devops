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
PNPM_ENTRY = re.compile(r"^  ['\"]?(.+?)@(\d+)\.(\d+)\.(\d+)[^:]*['\"]?:\s*$", re.M)
VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)")


def versions(lockfile: Path) -> dict[str, set[tuple[int, int, int]]]:
    """Read resolved versions without installing or invoking a package manager."""
    result: dict[str, set[tuple[int, int, int]]] = defaultdict(set)
    if lockfile.name == "uv.lock":
        for package in tomllib.loads(lockfile.read_text()).get("package", []):
            match = VERSION.match(package.get("version", ""))
            if match:
                result[package["name"].lower()].add(tuple(map(int, match.groups())))
    else:
        for match in PNPM_ENTRY.finditer(lockfile.read_text()):
            result[match.group(1)].add(tuple(map(int, match.groups()[1:])))
    return result


def safe_upgrade(before: dict, after: dict) -> bool:
    """Reject downgrades or major-version jumps for every changed package."""
    if not before or not after:
        return False
    for name, new_versions in after.items():
        old_versions = before.get(name)
        if not old_versions:
            continue  # Newly resolved transitive dependency, checked by OSV rescan.
        if any(
            not any(new[0] == old[0] and new >= old for old in old_versions)
            for new in new_versions
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
