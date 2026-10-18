#!/usr/bin/env bash

set -euox pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

# Supply-chain cooldown: avoid resolving/installing packages published within the last N days.
COOLDOWN_DAYS=7
export UV_EXCLUDE_NEWER="${COOLDOWN_DAYS} days"
export NPM_CONFIG_MIN_RELEASE_AGE="${COOLDOWN_DAYS}"
export PNPM_CONFIG_MINIMUM_RELEASE_AGE=$((COOLDOWN_DAYS * 24 * 60))

# Validate the narrowly scoped not-affected assessment before scanning dependencies.
SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIRECTORY}/check-qa-dependencies.sh"

# Scan dependency manifests and lockfiles before running QA tools.
osv_status=0
osv-scanner scan source --recursive --include-git-root . || osv_status=$?
if [[ "${osv_status}" -ne 0 && "${osv_status}" -ne 128 ]]; then
  exit "${osv_status}"
fi
PYTHON_LINE_LENGTH=88
RUFF_LINT_SELECT='ALL'
RUFF_LINT_IGNORE='CPY,RET,COM812,FBT001,FBT002'
RUFF_LINT_PER_FILE_IGNORES="lint.per-file-ignores = {'tests/**/*.py' = ['DOC201', 'DOC501', 'PLC2701', 'PLR0904', 'PLR2004', 'PLR6301', 'S101', 'S106', 'SLF001']}"

N_PYTHON_FILES=$(git ls-files -- '*.py' | wc -l)
if [[ "${N_PYTHON_FILES}" -gt 0 ]]; then
  PYPROJECT_FILE="$(git ls-files -- 'pyproject.toml' '*/pyproject.toml' | head -n 1)"
  if [[ -n "${PYPROJECT_FILE}" ]]; then
    PACKAGE_DIRECTORY="$(dirname "${PYPROJECT_FILE}")"
  else
    PACKAGE_DIRECTORY=''
  fi
  if [[ -n "${PACKAGE_DIRECTORY}" ]] && [[ -f "${PACKAGE_DIRECTORY}/uv.lock" ]]; then
    uv run --locked --directory "${PACKAGE_DIRECTORY}" ruff format .
    uv run --locked --directory "${PACKAGE_DIRECTORY}" ruff check --fix .
    uv run --locked --directory "${PACKAGE_DIRECTORY}" pyright .
  elif [[ -n "${PACKAGE_DIRECTORY}" ]] && [[ -f "${PACKAGE_DIRECTORY}/poetry.lock" ]]; then
    poetry -C "${PACKAGE_DIRECTORY}" run ruff format .
    poetry -C "${PACKAGE_DIRECTORY}" run ruff check --fix .
    poetry -C "${PACKAGE_DIRECTORY}" run pyright .
  elif [[ -n "${PACKAGE_DIRECTORY}" ]]; then
    uv run --locked ruff format "${PACKAGE_DIRECTORY}"
    uv run --locked ruff check --fix "${PACKAGE_DIRECTORY}"
    uv run --locked pyright "${PACKAGE_DIRECTORY}"
  else
    uv run --locked ruff format --preview --exclude=build --exclude=.venv "--line-length=${PYTHON_LINE_LENGTH}" .
    uv run --locked ruff check --fix --preview --exclude=build --exclude=.venv "--line-length=${PYTHON_LINE_LENGTH}" --select="${RUFF_LINT_SELECT}" --ignore="${RUFF_LINT_IGNORE}" --config "${RUFF_LINT_PER_FILE_IGNORES}" --config "lint.pydocstyle.convention = 'google'" --config 'lint.pylint.max-args = 10' --config 'lint.pylint.max-public-methods = 40' .

    (
      PYRIGHT_CONFIG_FILE="${REPO_ROOT}/.pyrightconfig.local-qa.$$.json"
      trap 'rm -f "${PYRIGHT_CONFIG_FILE}"' EXIT
      if [[ -d .venv ]]; then
        printf '%s\n' '{"include":["."],"exclude":["build",".venv"],"venvPath":".","venv":".venv","typeCheckingMode":"strict"}' > "${PYRIGHT_CONFIG_FILE}"
      else
        printf '%s\n' '{"include":["."],"exclude":["build",".venv"],"typeCheckingMode":"strict"}' > "${PYRIGHT_CONFIG_FILE}"
      fi
      uv run --locked pyright --threads=0 --project "${PYRIGHT_CONFIG_FILE}"
    )
  fi
fi

N_BASH_FILES=$(git ls-files -- '*.sh' '*.bash' '*.bats' | wc -l)
if [[ "${N_BASH_FILES}" -gt 0 ]]; then
  git ls-files -z -- '*.sh' '*.bash' '*.bats' \
    | xargs -0 -t shfmt --write --indent=2 --binary-next-line --case-indent --space-redirects
  git ls-files -z -- '*.sh' '*.bash' '*.bats' \
    | xargs -0 -t shellcheck
fi

N_TYPESCRIPT_FILES=$(git ls-files -- '*.ts' '*.tsx' '*.mts' '*.cts' | wc -l)
N_JAVASCRIPT_FILES=$(git ls-files -- '*.js' '*.jsx' '*.mjs' '*.cjs' | wc -l)
N_HTML_FILES=$(git ls-files -- '*.html' '*.htm' | wc -l)
N_MARKDOWN_FILES=$(git ls-files -- '*.md' '*.mdx' | wc -l)
if [[ "${N_TYPESCRIPT_FILES}" -gt 0 ]] || [[ "${N_JAVASCRIPT_FILES}" -gt 0 ]]; then
  PACKAGE_JSON_FILE=$(git ls-files -- 'package.json' '*/package.json' | head -n 1)
  if [[ -n "${PACKAGE_JSON_FILE}" ]]; then
    PACKAGE_DIRECTORY="$(dirname "${PACKAGE_JSON_FILE}")"
    NODE_MODULES_BIN="${PACKAGE_DIRECTORY}/node_modules/.bin"
    TSCONFIG_JSON_FILE="${PACKAGE_DIRECTORY}/tsconfig.json"
    PATH="${NODE_MODULES_BIN}:${PATH}"
  else
    PACKAGE_DIRECTORY='.'
    TSCONFIG_JSON_FILE='./tsconfig.json'
  fi

  if command -v biome > /dev/null 2>&1; then
    pnpm exec biome check --write "${PACKAGE_DIRECTORY}"
  fi
  if command -v prettier > /dev/null 2>&1 && ! command -v biome > /dev/null 2>&1; then
    pnpm exec prettier --write "${PACKAGE_DIRECTORY}/**/*.{js,jsx,mjs,cjs,ts,tsx,mts,cts,json,css,scss,md,mdx,html,htm}"
  fi
  if command -v oxlint > /dev/null 2>&1; then
    if [[ -f "${TSCONFIG_JSON_FILE}" ]]; then
      pnpm exec oxlint --fix --type-aware --tsconfig "${TSCONFIG_JSON_FILE}" "${PACKAGE_DIRECTORY}"
    else
      pnpm exec oxlint --fix "${PACKAGE_DIRECTORY}"
    fi
  fi
  if command -v eslint > /dev/null 2>&1; then
    pnpm exec eslint --fix --ext .js,.jsx,.mjs,.cjs,.ts,.tsx,.mts,.cts --no-error-on-unmatched-pattern "${PACKAGE_DIRECTORY}"
  fi

  if [[ "${N_TYPESCRIPT_FILES}" -gt 0 ]]; then
    if [[ -f "${TSCONFIG_JSON_FILE}" ]]; then
      pnpm exec tsc --noEmit --project "${TSCONFIG_JSON_FILE}"
    else
      pnpm exec tsc --noEmit
    fi
  fi
else
  if [[ "${N_HTML_FILES}" -gt 0 ]]; then
    pnpm exec prettier --write './**/*.{html,htm}'
  fi
  if [[ "${N_MARKDOWN_FILES}" -gt 0 ]]; then
    pnpm exec prettier --write './**/*.{md,mdx}'
  fi
fi

if [[ "${N_MARKDOWN_FILES}" -gt 0 ]]; then
  if [[ -f .markdownlint.jsonc ]]; then
    git ls-files -z -- '*.md' '*.mdx' | xargs -0 -t pnpm exec markdownlint --fix --config .markdownlint.jsonc
  else
    (
      trap 'rm -f .markdownlint.jsonc' EXIT
      printf '%s\n' '{"MD013":false,"MD033":false,"MD041":false}' > .markdownlint.jsonc
      git ls-files -z -- '*.md' '*.mdx' | xargs -0 -t pnpm exec markdownlint --fix --config .markdownlint.jsonc
    )
  fi
fi

while IFS= read -r GO_MOD_FILE; do
  GO_DIRECTORY="$(dirname "${GO_MOD_FILE}")"
  GOLANGCI_CONFIG_PATHS=()
  SEARCH_DIRECTORY="${GO_DIRECTORY}"
  while true; do
    if [[ "${SEARCH_DIRECTORY}" != '.' ]]; then
      GOLANGCI_CONFIG_PATHS+=("${SEARCH_DIRECTORY}/.golangci.yml")
    else
      GOLANGCI_CONFIG_PATHS+=('.golangci.yml')
    fi
    if [[ "${SEARCH_DIRECTORY}" == '.' ]]; then
      break
    fi
    SEARCH_DIRECTORY="$(dirname "${SEARCH_DIRECTORY}")"
  done
  GOLANGCI_CONFIG_FILE="$(git ls-files -- "${GOLANGCI_CONFIG_PATHS[@]}" | head -n 1)"
  if [[ -n "${GOLANGCI_CONFIG_FILE}" ]]; then
    GOLANGCI_LINT_CONFIG_ARGS=(-c "${REPO_ROOT}/${GOLANGCI_CONFIG_FILE}")
  else
    GOLANGCI_LINT_CONFIG_ARGS=()
  fi
  (
    cd "${GO_DIRECTORY}"
    golangci-lint "${GOLANGCI_LINT_CONFIG_ARGS[@]}" fmt --enable=gofumpt --enable=goimports
    golangci-lint "${GOLANGCI_LINT_CONFIG_ARGS[@]}" run --fix
    govulncheck ./...
    gosec ./...
  )
done < <(git ls-files -- 'go.mod' '*/go.mod')

if [[ -d '.github/workflows' ]]; then
  ZIZMOR_PATHS=('.github/workflows')
  [[ -d '.github/actions' ]] && ZIZMOR_PATHS+=('.github/actions')
  uv run --locked zizmor --fix=safe "${ZIZMOR_PATHS[@]}"
  N_WORKFLOW_YAML_FILES=$(git ls-files -- '.github/workflows/**.yml' '.github/workflows/**.yaml' | wc -l)
  if [[ "${N_WORKFLOW_YAML_FILES}" -gt 0 ]]; then
    # Reuse this repository's tested compatibility exceptions for newer GitHub.com syntax.
    ACTIONLINT_SCRIPT="$(yq -r '.jobs."github-actions-lint-scan".steps[] | select(.name == "Execute actionlint") | .run' .github/workflows/github-actions-lint-and-scan.yml)"
    [[ -n "${ACTIONLINT_SCRIPT}" && "${ACTIONLINT_SCRIPT}" != null ]]
    ACTIONLINT_COMPATIBILITY_MODE=true ACTIONLINT_EXTRA_IGNORE_REGEX='' \
      GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}" SEARCH_PATH=.github/workflows \
      bash -euo pipefail -c "${ACTIONLINT_SCRIPT}"
    git ls-files -z -- '.github/workflows/*.yml' '.github/workflows/*.yaml' \
      | xargs -0 -t uv run --locked yamllint -d '{"extends": "relaxed", "rules": {"line-length": "disable"}}'
  fi
fi

N_TERRAFORM_FILES=$(git ls-files -- '*.tf' '*.hcl' | wc -l)
if [[ "${N_TERRAFORM_FILES}" -gt 0 ]]; then
  terraform fmt -recursive .
  terragrunt hcl format --diff --working-dir .
  tflint --recursive --chdir=.
fi

N_DOCKER_FILES=$(git ls-files -- 'Dockerfile' '*/Dockerfile' | wc -l)
if [[ -d '.github/workflows' ]] || [[ "${N_TERRAFORM_FILES}" -gt 0 ]] || [[ "${N_DOCKER_FILES}" -gt 0 ]]; then
  uv run --locked checkov --framework=all --output=github_failed_only --directory=.
fi
if [[ "${N_TERRAFORM_FILES}" -gt 0 ]] || [[ "${N_DOCKER_FILES}" -gt 0 ]]; then
  TRIVY_DISABLE_TELEMETRY=true TRIVY_SKIP_VERSION_CHECK=true \
    trivy filesystem --scanners vuln,secret,misconfig --skip-dirs .venv --skip-dirs .terraform --skip-dirs .terragrunt-cache --skip-dirs node_modules --skip-dirs .git .
fi

N_SEMGREP_FILES=$(git ls-files -- '*.py' '*.go' '*.js' '*.jsx' '*.mjs' '*.cjs' '*.ts' '*.tsx' '*.mts' '*.cts' '*.sh' '*.bash' '*.bats' '*.tf' '*.hcl' '*.yml' '*.yaml' '*.html' '*.htm' 'Dockerfile*' '*.dockerfile' | wc -l)
if [[ "${N_SEMGREP_FILES}" -gt 0 ]]; then
  # Process workers avoid native OCaml thread startup failures on constrained runners.
  uv run --locked semgrep scan --x-parmap --jobs 2 --config p/default --metrics off --error .
fi
