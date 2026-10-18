---
name: local-qa
description: Run local QA including formatting and linting for the repository. Use whenever any file has been updated.
disable-model-invocation: false
---

# Local QA (format and lint)

Run the local QA script `scripts/qa.sh` in this skill.

## Procedure

- Execute the script exactly as shown above when this skill is triggered.
- Capture and summarize key output (success/failure, major warnings, and any files modified).
- If the script fails due to missing tooling (`command not found`, missing executable, or equivalent), install the missing tool(s) and rerun `./scripts/qa.sh`.
- If the install command uses `uv`, `npm`, or `pnpm`, set the same supply-chain cooldown env vars as `scripts/qa.sh` in the same shell command as the install, for example `UV_EXCLUDE_NEWER='7 days' NPM_CONFIG_MIN_RELEASE_AGE=7 PNPM_CONFIG_MINIMUM_RELEASE_AGE=10080 npm install -g <tool>`; setting them in an earlier, separate command does not carry the cooldown into the install.
- Install tools using this order of preference:
  1. Use the project's package manager when applicable (`uv`/`poetry` for Python, package manager scripts/dependencies for Node.js).
  2. Use a system package manager (`brew` on macOS, `apt` on Debian/Ubuntu) when project-local install is not applicable.
  3. Use language-specific installers as fallback (`pipx`/`pip`, `npm`, `go install`, etc.).
- If multiple tools are missing, repeat install -> rerun until QA completes or you hit a blocker.
- If installation fails or requires unavailable privileges, report what was attempted, the exact failure, and stop.
- Do not run unrelated commands; only run commands needed for QA and missing-tool installation.

## Dependency vulnerability remediation

- OSV scans run before other QA. On findings, `qa.sh` attempts one bounded, non-interactive update of affected `uv.lock` (using `uv lock --upgrade-package`) or `pnpm-lock.yaml` (using `pnpm update --lockfile-only --no-save --ignore-scripts`), then rescans.
- Only clean, tracked lockfiles are eligible. Updates respect the existing seven-day release cooldown and reject detected major-version jumps or downgrades; failed updates are rolled back. No manifest constraints, overrides, or ignore lists are changed automatically.
- Unsupported ecosystems, unfixable vulnerabilities, and remaining OSV findings still fail QA. Do not suppress or bypass scan failures; report remaining issues separately from successful lockfile changes. Avoid running on untrusted repositories with untrusted package manager configuration.
