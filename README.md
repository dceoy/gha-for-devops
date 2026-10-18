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
| [scorecard-assessment.yml](.github/workflows/scorecard-assessment.yml)                                           | OpenSSF Scorecard assessment                                      |
| [security-audit.yml](.github/workflows/security-audit.yml)                                                       | Deep security audit                                               |
| [security-pr.yml](.github/workflows/security-pr.yml)                                                             | Security PR checks                                                |
| [shell-lint.yml](.github/workflows/shell-lint.yml)                                                               | Lint for Shell                                                    |
| [source-security-scan.yml](.github/workflows/source-security-scan.yml)                                           | Source security scan                                              |
| [terraform-deploy-to-aws.yml](.github/workflows/terraform-deploy-to-aws.yml)                                     | Deployment of AWS resources using Terraform                       |
| [terraform-format-and-pr.yml](.github/workflows/terraform-format-and-pr.yml)                                     | Formatting for Terraform                                          |
| [terraform-lint-and-scan.yml](.github/workflows/terraform-lint-and-scan.yml)                                     | Lint and security scan for Terraform                              |
| [terraform-lock-files-upgrade-and-pr-merge.yml](.github/workflows/terraform-lock-files-upgrade-and-pr-merge.yml) | Upgrade of Terraform lock files and pull request merge            |
| [terraform-lock-files-upgrade.yml](.github/workflows/terraform-lock-files-upgrade.yml)                           | Upgrade of Terraform lock files                                   |
| [terragrunt-aws-switch-resources.yml](.github/workflows/terragrunt-aws-switch-resources.yml)                     | Switcher to apply or destroy AWS resources using Terragrunt       |
| [toml-lint.yml](.github/workflows/toml-lint.yml)                                                                 | Lint for TOML                                                     |
| [trivy-scan.yml](.github/workflows/trivy-scan.yml)                                                               | Trivy scan and dependency submission                              |
| [typescript-package-format-and-pr.yml](.github/workflows/typescript-package-format-and-pr.yml)                   | Formatting for TypeScript                                         |
| [typescript-package-lint-and-scan.yml](.github/workflows/typescript-package-lint-and-scan.yml)                   | Lint and security scan for TypeScript                             |
| [typescript-package-script.yml](.github/workflows/typescript-package-script.yml)                                 | Package script run for a TypeScript project                       |
| [web-api-monitoring-with-slack.yml](.github/workflows/web-api-monitoring-with-slack.yml)                         | Synthetic web API monitoring with Slack notification              |
| [web-dast-scan.yml](.github/workflows/web-dast-scan.yml)                                                         | Web DAST scan                                                     |
| [weekly-release.yml](.github/workflows/weekly-release.yml)                                                       | Weekly release                                                    |
| [yaml-lint.yml](.github/workflows/yaml-lint.yml)                                                                 | Lint for YAML                                                     |

## Security Workflows

| Use case                       | Workflow                 | Checks                                                      |
| ------------------------------ | ------------------------ | ----------------------------------------------------------- |
| Pull requests                  | `security-pr.yml`        | OSV-Scanner, Trivy, Semgrep, TruffleHog commit range        |
| Scheduled/manual audits        | `security-audit.yml`     | Source scan, Git history, CodeQL, Scorecard; optional Joern |
| Container releases             | `container-security.yml` | Trivy image scan, then Cosign signature verification        |
| Authorized staging/API testing | `web-dast-scan.yml`      | OWASP ZAP                                                   |

PR checks need `contents: read`. Audits skip PR events; set `codeql-languages` and grant `contents: read`, `actions: read`, and `security-events: write` for the default jobs. Enable Joern with `use-joern: true`.

Container verification needs digest-pinned `image-refs-json` and either `certificate-identity` or `certificate-identity-regexp`. For scans without signature verification, set `verify-signatures: false`. Use ZAP only for explicitly authorized non-production targets.

Language lint workflows share `source-security-scan.yml`. Trivy runs once per target and converts its JSON into reports and optional dependency snapshots. Summaries omit secret values; full reports may contain sensitive matches, so upload them only when needed with `trivy-report-artifact-name`.

`docker-lint-and-scan.yml` and `terraform-lint-and-scan.yml` can publish the dependency snapshot from their existing Trivy scan: set `submit-dependencies: true`, optionally set `snapshot-correlator`, and grant `contents: write` to the caller job. The scan jobs explicitly use read-only permissions, and publication is gated to trusted default-branch events. Do not add a separate source dependency-submission job.

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

Docker build, multi-target, and Bake workflows reuse their postbuild scan for publication. Set `submit-dependencies: true` and `push: true`; grant `contents: write` and `packages: read` for GHCR, and pass `DOCKER_TOKEN` for registry access. Avoid submitting the same inventory twice.

## Local QA

Install the tools in `mise.toml`, then run:

```sh
uv sync --locked
pnpm install --frozen-lockfile
pnpm qa
```

QA uses committed lockfiles and a seven-day dependency release cooldown. See [osv-scanner.toml](osv-scanner.toml) for the temporary Checkov/ecdsa vulnerability assessment, guarded scope, and expiration.

## License

[MIT License](LICENSE)

Copyright (c) 2024 Daichi Narushima
