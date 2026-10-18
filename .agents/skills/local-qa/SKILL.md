---
name: local-qa
description: Run repository QA after file changes, automatically diagnose and repair any failed check, and rerun until it passes or a documented blocker remains.
disable-model-invocation: false
---

# Local QA

Run the repository's `scripts/qa.sh` after changes. The script defines the required checks; this skill owns diagnosis, remediation, and retries for **every** failure, regardless of which tool failed. Do not embed scanner-specific repair logic in the script.

## Procedure

1. Record the initial working-tree status and preserve pre-existing changes. Run `./scripts/qa.sh` from the repository root, capturing the exit status and relevant output.
2. On **any nonzero exit**, identify the failing command, underlying cause, and affected files or dependencies. Use the failure output and targeted inspection; distinguish a reproducible defect from a transient infrastructure failure. Do not stop merely because the failure predates the current changes.
3. Attempt the smallest evidence-backed, in-scope repair that can address the cause:
   - **Formatting, lint, types, tests, builds, or configuration:** fix the affected source/configuration and use the repository's supported fixers or test commands.
   - **Dependency or security scans:** identify affected packages/advisories and available safe versions; update manifests/lockfiles using the declared package manager when compatible, then validate the result. Treat existing and newly introduced findings consistently, but do not broaden unrelated changes without authorization.
   - **Missing or broken tooling:** restore declared dependencies via the project's package manager or tool manager (for example, mise, uv, or pnpm). Use a system package manager only when permitted; do not require elevated privileges.
   - **Network, registry, environment, or external-service errors:** investigate and retry a transient operation once when safe, or use a supported equivalent mechanism that preserves the check.
4. After a repair, run a focused check that reproduces the failed condition, then **rerun the entire `./scripts/qa.sh`**. Address the next failure in the same way, even if it comes from a different tool. Continue until the full QA run succeeds or a stop condition applies.
5. Limit remediation to **3 materially distinct attempts per root cause** and **12 full QA runs per invocation**. Count attempts and retain findings across reruns; never loop on an unchanged, reproducible failure. A tool/install failure follows the same recovery process and limits.
6. Report the final QA status, attempted fixes, files changed, remaining failed command(s), and concrete reason for any blocker. Never claim QA passed unless a full post-repair run exited successfully.

## Safety

- Keep changes relevant to the requested task and QA findings. Preserve unrelated or user-authored work; inspect diffs and revert only this skill's unsuccessful changes, never unrelated edits.
- Preserve required checks, vulnerability gates, release-age restrictions, and lockfile integrity. Do not hide findings, add ignore/suppression rules, weaken lint/tests, bypass controls, or silently perform breaking/major upgrades to make QA green.
- For installs and dependency changes, honor the repository's existing supply-chain cooldown. If invoking uv, npm, or pnpm, set the same cooldown environment variables **in that command's shell environment** as in `scripts/qa.sh` (`UV_EXCLUDE_NEWER='7 days'`, `NPM_CONFIG_MIN_RELEASE_AGE=7`, `PNPM_CONFIG_MINIMUM_RELEASE_AGE=10080`) unless project configuration already enforces them.
- Stop only when a repair is unsafe, requires authorization or unavailable privileges, has no supported fix, is outside authorized scope, or the retry limits are exhausted. State the blocker explicitly; leave unresolved QA failures failing.
