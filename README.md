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

For production use, replace `@main` with a release tag or commit SHA. Pass sensitive values through `secrets:`, never `with:`. Cache-enabled workflows document options such as `enable-cache`, `cache-dependency-path`, and `cache-salt` in their workflow files.

### GitHub Pages

For a conventional Hugo site, call the combined build and deployment workflow:

```yaml
jobs:
  deploy:
    permissions:
      contents: read
      id-token: write
      pages: write
    uses: dceoy/gha-for-devops/.github/workflows/hugo-deploy-to-gh-pages.yml@main
```

For a custom build, upload a Pages artifact in one job and reuse only the deployment contract:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: ./scripts/build-site.sh
      - uses: actions/upload-pages-artifact@fc324d3547104276b827a68afc52ff2a11cc49c9 # v5.0.0
        with:
          path: public

  deploy:
    needs: build
    permissions:
      id-token: write
      pages: write
    uses: dceoy/gha-for-devops/.github/workflows/github-pages-deploy.yml@main
```

### Go quality checks

Keep generic correctness checks separate from linting and vulnerability analysis, and retain repository-specific validation in a local job:

```yaml
jobs:
  lint-and-scan:
    permissions:
      contents: read
      security-events: write
    uses: dceoy/gha-for-devops/.github/workflows/go-package-lint-and-scan.yml@main

  test:
    permissions:
      contents: read
    uses: dceoy/gha-for-devops/.github/workflows/go-package-test.yml@main
    with:
      race-enabled: true
      coverage-enabled: true
      upload-coverage: true

  validate-config:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: go run ./cmd/example validate ./config.yml
```

### Shell project CI

Replace a small shell project's local tool installation and version pinning with one reusable workflow that installs ShellCheck, shfmt, actionlint, Bats, zizmor, yamllint, and Checkov, then runs your QA command:

```yaml
jobs:
  ci:
    permissions:
      contents: read
    uses: dceoy/gha-for-devops/.github/workflows/shell-project-ci.yml@main
    with:
      command: .agents/skills/local-qa/scripts/qa.sh
```

### Repository security gate

Call the repository security workflow from the caller repository and choose the trigger there:

```yaml
name: Repository security
on:
  pull_request:

jobs:
  security:
    permissions:
      contents: read
      actions: read
      security-events: write
    uses: dceoy/gha-for-devops/.github/workflows/repository-security-scan.yml@<commit-sha>
```

The reusable workflow composes the existing GitHub Actions and shell lint reusable workflows and adds a Trivy filesystem scan for vulnerabilities, secrets, and misconfigurations. Repository-specific security policy, organization ruleset wiring, cross-repository orchestration, and evidence aggregation belong outside `gha-for-devops`.

### Generated file update pull requests

Run the `create-generated-update-pr` composite action as a step after your own generation and validation steps, in the same job and workspace, to open or refresh a pull request for the resulting changes. It requires `contents: write` and `pull-requests: write`, and reads `GH_TOKEN` from the step environment rather than an action input; the action runs `gh auth setup-git` internally, so `actions/checkout` does not need `persist-credentials: true`:

```yaml
jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: ./scripts/generate-docs.sh
      - uses: dceoy/gha-for-devops/.github/actions/create-generated-update-pr@main
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          paths: |
            docs/**
          branch: update-generated-docs
          base: main
          title: Update generated docs
```

Only the pathspecs listed in `paths` are ever staged or committed; unrelated workspace changes are left untouched. Re-running the action resets the same branch and updates the same open pull request instead of creating duplicates; if a later run finds no scoped changes, it closes that pull request instead of leaving it open with a stale diff. The generation step must run with `base` checked out (or a commit already merged into `base`); the action compares the checked-out commit against `base` on GitHub and fails before pushing anything if it is ahead of or diverged from `base`, so a mismatched checkout can never smuggle unrelated commits into the branch or pull request. See the action's `action.yml` for the full set of inputs (commit message, labels, draft mode, Git author) and outputs (`changed`, `branch`, `commit-sha`, `pr-number`, `pr-url`).

## Reusable Workflows

Each workflow below exposes `workflow_call`; see its file for supported inputs, secrets, permissions, and defaults.

| Workflow File                                                                                                    | Description                                                       |
| ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| [aws-cloudformation-lint.yml](.github/workflows/aws-cloudformation-lint.yml)                                     | Lint for AWS CloudFormation                                       |
| [aws-codebuild-run.yml](.github/workflows/aws-codebuild-run.yml)                                                 | Build using an AWS CodeBuild project                              |
| [aws-parameter-store-update.yml](.github/workflows/aws-parameter-store-update.yml)                               | Update AWS Parameter Store values                                 |
| [bats-test.yml](.github/workflows/bats-test.yml)                                                                 | Test for Bats                                                     |
| [claude-code-bot.yml](.github/workflows/claude-code-bot.yml)                                                     | Mention bot using Claude Code                                     |
| [claude-code-review.yml](.github/workflows/claude-code-review.yml)                                               | Pull request review using Claude Code                             |
| [dependabot-auto-merge.yml](.github/workflows/dependabot-auto-merge.yml)                                         | Dependabot auto-merge                                             |
| [docker-build-and-push.yml](.github/workflows/docker-build-and-push.yml)                                         | Docker image build and push                                       |
| [docker-build-with-multi-targets.yml](.github/workflows/docker-build-with-multi-targets.yml)                     | Docker image build and save for multiple build targets            |
| [docker-buildx-bake.yml](.github/workflows/docker-buildx-bake.yml)                                               | Docker image build from a bake definition file                    |
| [docker-image-scan.yml](.github/workflows/docker-image-scan.yml)                                                 | Security scan for Docker images                                   |
| [docker-lint-and-scan.yml](.github/workflows/docker-lint-and-scan.yml)                                           | Lint and security scan for Dockerfile                             |
| [docker-pull-from-aws.yml](.github/workflows/docker-pull-from-aws.yml)                                           | Docker image pull from AWS                                        |
| [docker-save-and-terraform-deploy-to-aws.yml](.github/workflows/docker-save-and-terraform-deploy-to-aws.yml)     | Docker image save and resource deployment to AWS using Terraform  |
| [gcloud-infra-manager-deployments.yml](.github/workflows/gcloud-infra-manager-deployments.yml)                   | Deployment of Google Cloud resources using Infrastructure Manager |
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
| [microsoft-defender-for-devops.yml](.github/workflows/microsoft-defender-for-devops.yml)                         | Microsoft Defender for Devops                                     |
| [opencode-bot.yml](.github/workflows/opencode-bot.yml)                                                           | Mention bot using OpenCode                                        |
| [opencode-review.yml](.github/workflows/opencode-review.yml)                                                     | Pull request review using OpenCode                                |
| [pr-agent.yml](.github/workflows/pr-agent.yml)                                                                   | PR-agent                                                          |
| [python-package-format-and-pr.yml](.github/workflows/python-package-format-and-pr.yml)                           | Formatting for Python                                             |
| [python-package-lint-and-scan.yml](.github/workflows/python-package-lint-and-scan.yml)                           | Lint and security scan for Python                                 |
| [python-package-mkdocs-gh-deploy.yml](.github/workflows/python-package-mkdocs-gh-deploy.yml)                     | Build and deployment of MkDocs documentation                      |
| [python-package-release-on-pypi-and-github.yml](.github/workflows/python-package-release-on-pypi-and-github.yml) | Python package release on PyPI and GitHub                         |
| [python-package-test.yml](.github/workflows/python-package-test.yml)                                             | Test for Python Package                                           |
| [python-pyinstaller.yml](.github/workflows/python-pyinstaller.yml)                                               | Build using PyInstaller                                           |
| [r-package-format-and-pr.yml](.github/workflows/r-package-format-and-pr.yml)                                     | Formatting for R                                                  |
| [r-package-lint.yml](.github/workflows/r-package-lint.yml)                                                       | Lint for R                                                        |
| [repository-security-scan.yml](.github/workflows/repository-security-scan.yml)                                   | Repository security                                               |
| [shell-lint.yml](.github/workflows/shell-lint.yml)                                                               | Lint for Shell                                                    |
| [shell-project-ci.yml](.github/workflows/shell-project-ci.yml)                                                   | Run shell project CI                                              |
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
| [yaml-lint.yml](.github/workflows/yaml-lint.yml)                                                                 | Lint for YAML                                                     |

## License

[MIT License](LICENSE)

Copyright (c) 2024 Daichi Narushima
