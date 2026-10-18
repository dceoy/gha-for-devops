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

For production use, pin a release tag or commit SHA instead of `@main`. Configure inputs with `with:`, pass credentials via `secrets:`, and grant the required `permissions:`. Consult each workflow file for its interface and defaults.

## Reusable Workflows

Each workflow below exposes `workflow_call`; see its file for supported inputs, secrets, permissions, and defaults.

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
| [trivy-scan.yml](.github/workflows/trivy-scan.yml)                                                         | Shared Trivy scan and dependency snapshot                           |
| [typescript-package-lint-and-scan.yml](.github/workflows/typescript-package-lint-and-scan.yml)                   | Lint and security scan for TypeScript                             |
| [typescript-package-script.yml](.github/workflows/typescript-package-script.yml)                                 | Package script run for a TypeScript project                       |
| [web-api-monitoring-with-slack.yml](.github/workflows/web-api-monitoring-with-slack.yml)                         | Synthetic web API monitoring with Slack notification              |
| [web-dast-scan.yml](.github/workflows/web-dast-scan.yml)                                                         | Web DAST scan                                                     |
| [weekly-release.yml](.github/workflows/weekly-release.yml)                                                       | Weekly release                                                    |
| [yaml-lint.yml](.github/workflows/yaml-lint.yml)                                                                 | Lint for YAML                                                     |

## Security Workflows

Choose by **execution use case**, not by the individual scanner:

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

For scheduled or manually triggered audits, call `security-audit.yml`. Specify project-specific `codeql-languages`; enable the more expensive Joern scan with `use-joern: true`. Deep audits skip pull-request events. Callers using the default CodeQL and Scorecard jobs must grant `contents: read`, `actions: read`, and `security-events: write`.

For release verification, call `container-security.yml` with `image-refs-json` (JSON array of immutable `@sha256:` references) and `certificate-identity` or `certificate-identity-regexp`. Signature verification runs only after successful image scanning. Set `verify-signatures: false` explicitly for non-release/tag-based scans. Container security scans run with `contents: read`. Docker build workflows reuse their existing postbuild Trivy scan for Dependency Graph reporting; `dependency-submission.yml` is an internal snapshot publisher and does not scan images or source. Before deployment, use digest-pinned image references and an expected signer identity.

Language-specific `*-lint-and-scan.yml` workflows continue handling language tooling, while OSV-Scanner, Trivy, Semgrep, and Checkov share the `source-security-scan.yml` implementation. The shared `trivy-scan.yml` runs Trivy once per filesystem or image target with all configured scanners. It converts the local JSON to a table or SARIF report and, when requested, a GitHub dependency snapshot without rescanning. Raw JSON is not uploaded because secret matches may contain sensitive data. Set `trivy-report-artifact-name` only when you want to retain the full SARIF artifact, which may contain sensitive matches.

Docker image builds can publish immutable, digest-pinned inventories without another Trivy scan. The postbuild scan runs even if `scan-after-build: false` when dependency submission is requested on a trusted push. Set `submit-dependencies: true` and `push: true` on `docker-build-and-push.yml`, `docker-build-with-multi-targets.yml`, or `docker-buildx-bake.yml`. Multi-target builds scan shared source once before the build matrix. Publication runs only on trusted events targeting the default branch and remains opt-in by default. Bake publishes a separate snapshot for each pushed target with a digest in its build metadata. The caller must allow `contents: write` (and `packages: read` for GHCR) and pass `DOCKER_TOKEN` for registry access. Do not also submit the same image in a separate caller job.

Dependency Graph publication is restricted to trusted default-branch `push`, `schedule`, or `workflow_dispatch` events; PR events cannot publish. The Docker build workflows manage the separate read-only scan and write-only publisher jobs automatically. For filesystem inventories, call `trivy-scan.yml` and then publish its snapshot artifact from a trusted caller job, for example:

```yaml
jobs:
  scan:
    uses: dceoy/gha-for-devops/.github/workflows/trivy-scan.yml@<pinned-ref>
    permissions:
      contents: read
    with:
      scan-type: filesystem
      scan-ref: .
      submit-dependencies: true
      snapshot-correlator: source-root
      snapshot-artifact-prefix: source
  publish:
    needs: scan
    uses: dceoy/gha-for-devops/.github/workflows/dependency-submission.yml@<pinned-ref>
    permissions:
      contents: write
    with:
      snapshot-artifact-name: source-dependency-snapshot-0
```

The publisher validates trusted events and the default branch. Configure the caller to run these jobs only on trusted events; avoid simultaneously running independent source dependency scans for the same target. This separation prevents untrusted scanner jobs from inheriting write permissions.

Security trust boundaries remain explicit: TruffleHog reports no secret values, public OpenSSF Scorecard publication stays in the non-reusable repository-local `scorecard.yml`, OWASP ZAP is limited to explicitly authorized non-production targets, and Cosign verification requires a known signer identity. Cosign and BuildKit provenance do not establish SLSA compliance on their own.

**Breaking changes:** `docker-image-scan.yml`, `docker-image-verify.yml`, and `microsoft-defender-for-devops.yml` were removed. Migrate release callers to `container-security.yml` and drop the old `secrets: GH_TOKEN` mapping, which the replacement does not accept. Use `dependency-submission.yml` if Dependency Graph SBOM submission is still needed; use the shared source checks and CodeQL for static analysis.

## Local QA

Install local tools with `uv sync --locked` and `pnpm install --frozen-lockfile`, then run `pnpm qa`. Python and Node QA commands use the committed lockfiles, including fixed transitive dependencies. Dependency resolution retains the seven-day release cooldown.

The root `osv-scanner.toml` records one temporary not-affected assessment for Checkov 3.3.26 and `ecdsa` 0.19.2: Checkov only loads public keys and verifies signatures, which the [upstream Minerva advisory](https://github.com/tlsfuzzer/python-ecdsa/security/advisories/GHSA-wj6h-64fc-37mp) explicitly excludes. The package itself is not patched. A guard checks the reviewed artifact hashes, sole dependent, and absence of root runtime dependencies before QA; any change requires reassessment. This advisory-specific exception expires on 2026-11-17 and does not propagate to nested project directories.

## License

[MIT License](LICENSE)

Copyright (c) 2024 Daichi Narushima
