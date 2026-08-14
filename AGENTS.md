# Repository Guidelines

## Project Structure & Module Organization

This repository publishes reusable GitHub Actions workflows for DevOps tasks. The `workflows` symlink points to `.github/workflows/` for convenience. The generated public documentation is `README.md`, and its source template is `README.md.tmpl` (a `gomplate` template). The README generator is the shell script `.github/scripts/update-readme.sh`, which extracts reusable workflow metadata with `yq`, renders the template with `gomplate`, and formats the output with Prettier. Repository tool versions are declared in `mise.toml`. Local automation and agent instructions are under `.agents/`, including `.agents/skills/local-qa`.

## Build, Test, and Development Commands

- `mise install`: install the repository tools pinned in `mise.toml`.
- `.github/scripts/update-readme.sh`: regenerate root `README.md` from `README.md.tmpl` and `.github/workflows` (requires `yq`, `gomplate`, and `prettier` on `PATH`).
- `scripts/qa.sh`: run the local QA workflow defined by `.agents/skills/local-qa` after file changes.

## Coding Style & Naming Conventions

Keep workflow files in kebab-case with a `.yml` extension, for example `docker-build-and-push.yml`. Keep shell scripts in `bash` with `set -euo pipefail` and ShellCheck-clean. Prefer explicit `workflow_call` inputs and secrets, and keep action versions pinned as full commit SHAs with version comments when updating workflows.

Apply KISS, DRY, and YAGNI consistently. Keep reusable workflows small and explicit, share repeated logic only when duplication is real, and avoid inputs, jobs, or helper code that no current workflow needs. Prefer clear YAML and straightforward shell over speculative abstractions.

## Testing Guidelines

For README generator changes, run `.github/scripts/update-readme.sh` and review the regenerated `README.md`. For workflow changes, run `actionlint` when available and validate YAML formatting. Regenerate `README.md` whenever workflow names or descriptions change, then review the generated table.

## Commit & Pull Request Guidelines

Keep commits focused and describe user-visible workflow or documentation effects. PRs should include a concise summary, mention affected workflow files, link related issues when applicable, and note local checks run. Include screenshots only for documentation rendering changes where visual layout matters.

## Security & Configuration Tips

Never pass sensitive values through reusable workflow `with:` inputs; use `secrets:` so GitHub masks them in logs. Treat BuildKit secret names and file paths as non-sensitive metadata, and put actual secret values in repository or organization secrets.
