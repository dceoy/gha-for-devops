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

Pin a release tag or commit SHA in production. Set inputs with `with:`, credentials with `secrets:`, and required `permissions:`. See each workflow file for defaults.

## Reusable Workflows

Each workflow supports `workflow_call`.

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
| [dependency-submission.yml](.github/workflows/dependency-submission.yml)                                         | Submit dependencies to GitHub Dependency Graph                    |
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
| [typescript-package-format-and-pr.yml](.github/workflows/typescript-package-format-and-pr.yml)                   | Formatting for TypeScript                                         |
| [typescript-package-lint-and-scan.yml](.github/workflows/typescript-package-lint-and-scan.yml)                   | Lint and security scan for TypeScript                             |
| [typescript-package-script.yml](.github/workflows/typescript-package-script.yml)                                 | Package script run for a TypeScript project                       |
| [web-api-monitoring-with-slack.yml](.github/workflows/web-api-monitoring-with-slack.yml)                         | Synthetic web API monitoring with Slack notification              |
| [web-dast-scan.yml](.github/workflows/web-dast-scan.yml)                                                         | Web DAST scan                                                     |
| [weekly-release.yml](.github/workflows/weekly-release.yml)                                                       | Weekly release                                                    |
| [yaml-lint.yml](.github/workflows/yaml-lint.yml)                                                                 | Lint for YAML                                                     |

## Security Workflows

Choose a workflow for your use case:

| Use case                       | Reusable workflow        | Default checks                                              |
| ------------------------------ | ------------------------ | ----------------------------------------------------------- |
| Pull requests                  | `security-pr.yml`        | OSV-Scanner, Trivy, Semgrep and TruffleHog commit range     |
| Scheduled/manual deep audit    | `security-audit.yml`     | Source scan, Git history, CodeQL, Scorecard; optional Joern |
| Container release gate         | `container-security.yml` | Trivy image scan, then Cosign digest/signature verification |
| Authorized staging/API testing | `web-dast-scan.yml`      | OWASP ZAP with explicit authorization                       |

PR gate (pin a tag or commit SHA in production):

```yaml
jobs:
  security:
    uses: dceoy/gha-for-devops/.github/workflows/security-pr.yml@<pinned-ref>
    permissions:
      contents: read
    with:
      package-path: .
```

Call `security-audit.yml` for scheduled or manual audits. Set `codeql-languages` for your project and `use-joern: true` to enable Joern. The default CodeQL and Scorecard jobs require `contents: read`, `actions: read`, and `security-events: write`.

Call `container-security.yml` with `image-refs-json` containing digest-pinned image references and either `certificate-identity` or `certificate-identity-regexp`. It scans images before verifying signatures and requires `contents: read`. Set `verify-signatures: false` to scan without signature verification.

Language-specific lint workflows use `source-security-scan.yml` for shared security checks. Trivy summaries omit messages and code snippets to avoid exposing secrets. Set `trivy-report-artifact-name` to retain full SARIF, which may contain sensitive matches.

To submit Docker dependencies, set `submit-dependencies: true` and `push: true` on `docker-build-and-push.yml` or `docker-buildx-bake.yml`. Submission requires a trusted event targeting the default branch, `contents: write`, registry credentials via `DOCKER_TOKEN`, and `packages: read` for GHCR. Bake submits a snapshot per pushed target.

For separate Dependency Graph submissions, call `dependency-submission.yml` on trusted `push`, `schedule`, or `workflow_dispatch` events:

```yaml
jobs:
  dependencies:
    uses: dceoy/gha-for-devops/.github/workflows/dependency-submission.yml@<pinned-ref>
    permissions:
      contents: write
    with:
      scan-type: filesystem
      scan-ref: .
      snapshot-correlator: source-root
```

For container inventories, use `scan-type: image` with `image-ref`. Private registries also accept `registry`, `registry-user`, and `DOCKER_TOKEN`. For local images, set `image-artifact-name` to a current-run artifact containing `<name>.tar`. Use a distinct, stable `snapshot-correlator` per source directory or image target, and avoid duplicate submissions.

Use OWASP ZAP only on explicitly authorized non-production targets. Public Scorecard publication uses the repository-local `scorecard.yml`. Cosign verification requires a known signer; signatures and build provenance alone do not establish SLSA compliance.

## Local QA

Install tools with `uv sync --locked` and `pnpm install --frozen-lockfile`, then run `pnpm qa`. Dependencies use committed lockfiles and a seven-day release cooldown.

The root `osv-scanner.toml` temporarily marks Checkov 3.3.26's use of `ecdsa` 0.19.2 as unaffected by the [Minerva advisory](https://github.com/tlsfuzzer/python-ecdsa/security/advisories/GHSA-wj6h-64fc-37mp): Checkov only verifies signatures with public keys. The package remains unpatched. QA validates this assessment's scope and artifact hashes. The exception expires on 2026-11-17 and applies only to the root project.

## License

[MIT License](LICENSE)

Copyright (c) 2024 Daichi Narushima
