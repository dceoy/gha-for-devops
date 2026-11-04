# gha-for-devops

Reusable GitHub Actions workflows for CI/CD, security, infrastructure, and developer automation.

[![CI](https://github.com/dceoy/gha-for-devops/actions/workflows/ci.yml/badge.svg)](https://github.com/dceoy/gha-for-devops/actions/workflows/ci.yml)

## Usage

Call a reusable workflow from a job in your repository:

```yaml
name: YAML lint
on:
  pull_request:

jobs:
  lint:
    uses: dceoy/gha-for-devops/.github/workflows/yaml-lint.yml@main
```

Pin a release tag or commit SHA in production. Set `with:`, `secrets:`, and `permissions:` as documented in the workflow file.

## Reusable Workflows

See each workflow for inputs, secrets, permissions, and defaults.

| Workflow File                                                                                                    | Description                                                       |
| ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| [agent-skills-package.yml](.github/workflows/agent-skills-package.yml)                                           | Package agent skills                                              |
| [ansible-lint.yml](.github/workflows/ansible-lint.yml)                                                           | Lint for Ansible                                                  |
| [aws-cloudformation-lint.yml](.github/workflows/aws-cloudformation-lint.yml)                                     | Lint for AWS CloudFormation                                       |
| [aws-codebuild-run.yml](.github/workflows/aws-codebuild-run.yml)                                                 | Build using an AWS CodeBuild project                              |
| [aws-parameter-store-update.yml](.github/workflows/aws-parameter-store-update.yml)                               | Update AWS Parameter Store values                                 |
| [bats-test.yml](.github/workflows/bats-test.yml)                                                                 | Test for Bats                                                     |
| [claude-code-bot.yml](.github/workflows/claude-code-bot.yml)                                                     | Mention bot using Claude Code                                     |
| [claude-code-review.yml](.github/workflows/claude-code-review.yml)                                               | Pull request review using Claude Code                             |
| [container-security.yml](.github/workflows/container-security.yml)                                               | Container security scan and signature verification                |
| [dependabot-auto-merge.yml](.github/workflows/dependabot-auto-merge.yml)                                         | Dependabot auto-merge                                             |
| [docker-build-and-push.yml](.github/workflows/docker-build-and-push.yml)                                         | Docker image build and push                                       |
| [docker-build-with-multi-targets.yml](.github/workflows/docker-build-with-multi-targets.yml)                     | Docker image build and save for multiple build targets            |
| [docker-buildx-bake.yml](.github/workflows/docker-buildx-bake.yml)                                               | Docker image build from a bake definition file                    |
| [docker-lint-and-scan.yml](.github/workflows/docker-lint-and-scan.yml)                                           | Lint and security scan for Dockerfile                             |
| [docker-pull-from-aws.yml](.github/workflows/docker-pull-from-aws.yml)                                           | Docker image pull from AWS                                        |
| [docker-save-and-terraform-deploy-to-aws.yml](.github/workflows/docker-save-and-terraform-deploy-to-aws.yml)     | Docker image save and resource deployment to AWS using Terraform  |
| [gcloud-infra-manager-deployments.yml](.github/workflows/gcloud-infra-manager-deployments.yml)                   | Deployment of Google Cloud resources using Infrastructure Manager |
| [git-secret-scan.yml](.github/workflows/git-secret-scan.yml)                                                     | Git history secret scan                                           |
| [github-actions-lint-and-scan.yml](.github/workflows/github-actions-lint-and-scan.yml)                           | Lint and security scan for GitHub Actions workflows and actions   |
| [github-codeql-analysis.yml](.github/workflows/github-codeql-analysis.yml)                                       | GitHub CodeQL Analysis                                            |
| [github-major-version-tag.yml](.github/workflows/github-major-version-tag.yml)                                   | Major version tag on GitHub                                       |
| [github-pages-deploy.yml](.github/workflows/github-pages-deploy.yml)                                             | Deploy an artifact to GitHub Pages                                |
| [github-pr-branch-aggregation.yml](.github/workflows/github-pr-branch-aggregation.yml)                           | Aggregation of open pull request branches                         |
| [github-release.yml](.github/workflows/github-release.yml)                                                       | Release on GitHub                                                 |
| [go-package-lint-and-scan.yml](.github/workflows/go-package-lint-and-scan.yml)                                   | Lint and security scan for Go                                     |
| [go-package-release-on-github.yml](.github/workflows/go-package-release-on-github.yml)                           | Go package release on GitHub                                      |
| [go-package-test.yml](.github/workflows/go-package-test.yml)                                                     | Test a Go package                                                 |
| [html-lint-and-scan.yml](.github/workflows/html-lint-and-scan.yml)                                               | Lint and scan for HTML/CSS                                        |
| [hugo-deploy-to-gh-pages.yml](.github/workflows/hugo-deploy-to-gh-pages.yml)                                     | Build and deployment of Hugo site to GitHub Pages                 |
| [joern-scan.yml](.github/workflows/joern-scan.yml)                                                               | Static analysis with Joern                                        |
| [json-lint.yml](.github/workflows/json-lint.yml)                                                                 | Lint for JSON                                                     |
| [json-schema-validation.yml](.github/workflows/json-schema-validation.yml)                                       | Schema validation for JSON                                        |
| [markdown-format-and-pr.yml](.github/workflows/markdown-format-and-pr.yml)                                       | Formatting for Markdown                                           |
| [markdown-lint.yml](.github/workflows/markdown-lint.yml)                                                         | Lint for Markdown                                                 |
| [mise-lock-update.yml](.github/workflows/mise-lock-update.yml)                                                   | Update mise.lock and create a pull request                        |
| [python-package-format-and-pr.yml](.github/workflows/python-package-format-and-pr.yml)                           | Formatting for Python                                             |
| [python-package-lint-and-scan.yml](.github/workflows/python-package-lint-and-scan.yml)                           | Lint and security scan for Python                                 |
| [python-package-mkdocs-gh-deploy.yml](.github/workflows/python-package-mkdocs-gh-deploy.yml)                     | Build and deployment of MkDocs documentation                      |
| [python-package-release-on-pypi-and-github.yml](.github/workflows/python-package-release-on-pypi-and-github.yml) | Python package release on PyPI and GitHub                         |
| [python-package-test.yml](.github/workflows/python-package-test.yml)                                             | Test for Python Package                                           |
| [python-pyinstaller.yml](.github/workflows/python-pyinstaller.yml)                                               | Build using PyInstaller                                           |
| [r-package-format-and-pr.yml](.github/workflows/r-package-format-and-pr.yml)                                     | Formatting for R                                                  |
| [r-package-lint.yml](.github/workflows/r-package-lint.yml)                                                       | Lint for R                                                        |
| [renovate.yml](.github/workflows/renovate.yml)                                                                   | Renovate OSS                                                      |
| [scorecard-assessment.yml](.github/workflows/scorecard-assessment.yml)                                           | OpenSSF Scorecard assessment                                      |
| [security-audit.yml](.github/workflows/security-audit.yml)                                                       | Deep security audit                                               |
| [security-pr.yml](.github/workflows/security-pr.yml)                                                             | Security PR checks                                                |
| [shell-lint.yml](.github/workflows/shell-lint.yml)                                                               | Lint for Shell                                                    |
| [source-security-scan.yml](.github/workflows/source-security-scan.yml)                                           | Source security scan                                              |
| [syft-grype-scan.yml](.github/workflows/syft-grype-scan.yml)                                                     | Generate SBOM and scan with Grype                                 |
| [terraform-deploy-to-aws.yml](.github/workflows/terraform-deploy-to-aws.yml)                                     | Deployment of AWS resources using Terraform                       |
| [terraform-format-and-pr.yml](.github/workflows/terraform-format-and-pr.yml)                                     | Formatting for Terraform                                          |
| [terraform-lint-and-scan.yml](.github/workflows/terraform-lint-and-scan.yml)                                     | Lint and security scan for Terraform                              |
| [terraform-lock-files-upgrade.yml](.github/workflows/terraform-lock-files-upgrade.yml)                           | Upgrade of Terraform lock files                                   |
| [terragrunt-aws-switch-resources.yml](.github/workflows/terragrunt-aws-switch-resources.yml)                     | Switcher to apply or destroy AWS resources using Terragrunt       |
| [toml-lint.yml](.github/workflows/toml-lint.yml)                                                                 | Lint for TOML                                                     |
| [trivy-scan.yml](.github/workflows/trivy-scan.yml)                                                               | Trivy scan and dependency submission                              |
| [typescript-package-format-and-pr.yml](.github/workflows/typescript-package-format-and-pr.yml)                   | Formatting for TypeScript                                         |
| [typescript-package-lint-and-scan.yml](.github/workflows/typescript-package-lint-and-scan.yml)                   | Lint and security scan for TypeScript                             |
| [typescript-package-script.yml](.github/workflows/typescript-package-script.yml)                                 | Package script run for a TypeScript project                       |
| [web-api-monitoring-with-slack.yml](.github/workflows/web-api-monitoring-with-slack.yml)                         | Synthetic web API monitoring with Slack notification              |
| [web-dast-scan.yml](.github/workflows/web-dast-scan.yml)                                                         | Web DAST scan                                                     |
| [yaml-lint.yml](.github/workflows/yaml-lint.yml)                                                                 | Lint for YAML                                                     |

## Security Workflows

| Use case                       | Workflow                 | Checks                                                      |
| ------------------------------ | ------------------------ | ----------------------------------------------------------- |
| Pull requests                  | `security-pr.yml`        | OSV-Scanner, Trivy, Semgrep, TruffleHog commit range        |
| Scheduled/manual audits        | `security-audit.yml`     | Source scan, Git history, CodeQL, Scorecard; optional Joern |
| Container releases             | `container-security.yml` | Trivy, optional Syft + Grype, then Cosign verification      |
| Authorized staging/API testing | `web-dast-scan.yml`      | OWASP ZAP                                                   |

PR checks need `contents: read`. Audits skip PR events; set `codeql-languages` and grant `contents: read`, `actions: read`, and `security-events: write` for the default jobs. Enable Joern with `use-joern: true`.

Container verification needs digest-pinned `image-refs-json` and either `certificate-identity` or `certificate-identity-regexp`. For scans without signature verification, set `verify-signatures: false`. Use ZAP only for explicitly authorized non-production targets.

Language lint workflows share `source-security-scan.yml`. Trivy runs once per target and converts its JSON into reports and optional dependency snapshots. Summaries omit secret values; full reports may contain sensitive matches, so upload them only when needed with `trivy-report-artifact-name`.

`docker-lint-and-scan.yml`, `terraform-lint-and-scan.yml`, and `source-security-scan.yml` run their scans with read-only `contents` permission at both the workflow and job level. To publish dependencies, call `trivy-scan.yml` directly and grant `contents: write` to that caller job. Set `use-trivy: false` on `docker-lint-and-scan.yml` when invoking `trivy-scan.yml` separately to avoid duplicate scans.

### Dependency Graph

Use `trivy-scan.yml` to scan and publish dependencies:

```yaml
jobs:
  dependencies:
    uses: dceoy/gha-for-devops/.github/workflows/trivy-scan.yml@<pinned-ref>
    permissions:
      contents: write
    with:
      scan-ref: .
      submit-dependencies: true
      snapshot-correlator: source-root
```

Publication is opt-in and limited to default-branch `push`, `schedule`, or `workflow_dispatch` events. Scan jobs use `contents: read`; publication requires the caller to grant `contents: write`. Keep a distinct, stable correlator for each inventory.

When a scan finds no resolved package URLs, the workflow skips submission so an empty inventory does not replace the repository's existing dependency graph.

Docker build, multi-target, and Bake workflows reuse their postbuild scan for publication. Set `submit-dependencies: true` and `push: true`; grant `contents: write` and `packages: read` for GHCR, and pass `DOCKER_TOKEN` for registry access. Avoid submitting the same inventory twice.

## Renovate OSS

Use [Renovate OSS](https://docs.renovatebot.com/) without a hosted Renovate service. The reusable workflow processes only the caller repository; configure update rules in its `renovate.json`.

Schedule it from the calling repository (pin the reusable workflow to a release tag or commit SHA in production):

```yaml
name: Renovate
on:
  schedule:
    - cron: "0 3 * * *"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  renovate:
    uses: dceoy/gha-for-devops/.github/workflows/renovate.yml@<pinned-ref>
    secrets:
      RENOVATE_TOKEN: YOUR_RENOVATE_TOKEN_SECRET_EXPRESSION
```

For a GitHub App, omit `RENOVATE_TOKEN` and provide `RENOVATE_APP_ID` and `RENOVATE_APP_PRIVATE_KEY`. The generated token is limited to the caller repository and explicitly requests **Contents, Issues, Pull requests, Commit statuses, and Workflows: write**; the App installation must grant all five permissions. This supports Dependency Dashboard issues and GitHub Actions dependency updates without inheriting the App's unrelated permissions. Additional Renovate features (such as repository administration checks, Check runs, Dependabot alerts, organization team lookups, or merge queues) may require further permissions; extend this wrapper deliberately if those features are needed. For a fine-grained PAT, Renovate's GitHub documentation lists repository **Contents, Issues, Pull requests, Commit statuses, and Workflows: read/write**, **Dependabot alerts: read**, and organization **Members: read**; a classic PAT requires `repo` and, for workflow-file updates, `workflow` scope. Use a dedicated bot credential. Missing or conflicting credentials fail closed. Replace `YOUR_RENOVATE_TOKEN_SECRET_EXPRESSION` with a GitHub Actions expression referencing the caller's `RENOVATE_TOKEN` secret; map only the required secret(s) rather than inheriting all caller secrets.

Use a Docker-capable runner, and configure auto-merge explicitly in the caller's Renovate configuration if desired (disabled by default). Do not run Renovate and Dependabot on the same dependencies unless their responsibilities are intentionally separated. The workflow intentionally skips pull request events; run it on `schedule` or `workflow_dispatch`.

## Local QA

Install the tools in `mise.toml`, then run:

```sh
uv sync --locked
pnpm install --frozen-lockfile
pnpm qa
```

QA uses committed lockfiles and a one-day dependency release cooldown. See [osv-scanner.toml](osv-scanner.toml) for the temporary Checkov/ecdsa vulnerability assessment, guarded scope, and expiration.

## License

[MIT License](LICENSE)

Copyright (c) 2024 Daichi Narushima
