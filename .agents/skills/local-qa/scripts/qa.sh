#!/usr/bin/env bash

set -euox pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

# Supply-chain cooldown: avoid resolving/installing packages published within the last N days.
COOLDOWN_DAYS=7
export UV_EXCLUDE_NEWER="${COOLDOWN_DAYS} days"
export NPM_CONFIG_MIN_RELEASE_AGE="${COOLDOWN_DAYS}"
export PNPM_CONFIG_MINIMUM_RELEASE_AGE=$((COOLDOWN_DAYS * 24 * 60))

PYTHON_LINE_LENGTH=88
RUFF_LINT_EXTEND_SELECT='F,E,W,C90,I,N,D,UP,S,B,A,COM,C4,PT,Q,SIM,ARG,ERA,PD,PLC,PLE,PLW,TRY,FLY,NPY,PERF,FURB,RUF'
RUFF_LINT_IGNORE='D100,D103,D203,D213,S101,B008,A002,A004,COM812,PLC2701,TRY003'

N_PYTHON_FILES=$(git ls-files -- '*.py' | wc -l)
if [[ "${N_PYTHON_FILES}" -gt 0 ]]; then
  PYPROJECT_FILE="$(git ls-files -- 'pyproject.toml' '*/pyproject.toml' | head -n 1)"
  if [[ -n "${PYPROJECT_FILE}" ]]; then
    PACKAGE_DIRECTORY="$(dirname "${PYPROJECT_FILE}")"
  else
    PACKAGE_DIRECTORY=''
  fi
  if [[ -n "${PACKAGE_DIRECTORY}" ]] && [[ -f "${PACKAGE_DIRECTORY}/uv.lock" ]]; then
    uv run --directory "${PACKAGE_DIRECTORY}" ruff format .
    uv run --directory "${PACKAGE_DIRECTORY}" ruff check --fix .
    uv run --directory "${PACKAGE_DIRECTORY}" pyright .
  elif [[ -n "${PACKAGE_DIRECTORY}" ]] && [[ -f "${PACKAGE_DIRECTORY}/poetry.lock" ]]; then
    poetry -C "${PACKAGE_DIRECTORY}" run ruff format .
    poetry -C "${PACKAGE_DIRECTORY}" run ruff check --fix .
    poetry -C "${PACKAGE_DIRECTORY}" run pyright .
  elif [[ -n "${PACKAGE_DIRECTORY}" ]]; then
    uvx ruff format "${PACKAGE_DIRECTORY}"
    uvx ruff check --fix "${PACKAGE_DIRECTORY}"
    uvx pyright "${PACKAGE_DIRECTORY}"
  else
    uvx ruff format --exclude=build --exclude=.venv "--line-length=${PYTHON_LINE_LENGTH}" .
    uvx ruff check --fix --exclude=build --exclude=.venv "--line-length=${PYTHON_LINE_LENGTH}" --extend-select="${RUFF_LINT_EXTEND_SELECT}" --ignore="${RUFF_LINT_IGNORE}" .
    uvx pyright --threads=0 .
  fi
fi

N_BASH_FILES=$(git ls-files -- '*.sh' '*.bash' '*.bats' | wc -l)
if [[ "${N_BASH_FILES}" -gt 0 ]]; then
  git ls-files -z -- '*.sh' '*.bash' '*.bats' \
    | xargs -0 -t shfmt --write --indent=2 --binary-next-line --case-indent --space-redirects
  git ls-files -z -- '*.sh' '*.bash' '*.bats' \
    | xargs -0 -t shellcheck
fi

N_TYPESCRIPT_FILES=$(git ls-files -- '*.ts' '*.tsx' | wc -l)
N_JAVASCRIPT_FILES=$(git ls-files -- '*.js' '*.jsx' | wc -l)
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
    npx -y @biomejs/biome check --write "${PACKAGE_DIRECTORY}"
  fi
  if command -v prettier > /dev/null 2>&1 && ! command -v biome > /dev/null 2>&1; then
    npx -y prettier --write "${PACKAGE_DIRECTORY}/**/*.{js,jsx,ts,tsx,json,css,scss,md,mdx,html,htm}"
  fi
  if command -v oxlint > /dev/null 2>&1; then
    if [[ -f "${TSCONFIG_JSON_FILE}" ]]; then
      npx -y oxlint --fix --type-aware --tsconfig "${TSCONFIG_JSON_FILE}" "${PACKAGE_DIRECTORY}"
    else
      npx -y oxlint --fix "${PACKAGE_DIRECTORY}"
    fi
  fi
  if command -v eslint > /dev/null 2>&1; then
    npx -y eslint --fix --ext .js,.jsx,.ts,.tsx --no-error-on-unmatched-pattern "${PACKAGE_DIRECTORY}"
  fi

  if [[ "${N_TYPESCRIPT_FILES}" -gt 0 ]]; then
    if [[ -f "${TSCONFIG_JSON_FILE}" ]]; then
      npx -y --package typescript tsc --noEmit --project "${TSCONFIG_JSON_FILE}"
    else
      npx -y --package typescript tsc --noEmit
    fi
  fi
else
  if [[ "${N_HTML_FILES}" -gt 0 ]]; then
    npx -y prettier --write './**/*.{html,htm}'
  fi
  if [[ "${N_MARKDOWN_FILES}" -gt 0 ]]; then
    npx -y prettier --write './**/*.{md,mdx}'
  fi
fi

if [[ "${N_MARKDOWN_FILES}" -gt 0 ]]; then
  if [[ -f .markdownlint-cli2.jsonc ]]; then
    git ls-files -z -- '*.md' '*.mdx' | xargs -0 -t npx -y markdownlint-cli2 --fix --config .markdownlint-cli2.jsonc
  else
    printf '{"config":{"MD013":false,"MD033":false,"MD041":false}}' > .markdownlint-cli2.jsonc
    set +e
    git ls-files -z -- '*.md' '*.mdx' | xargs -0 -t npx -y markdownlint-cli2 --fix --config .markdownlint-cli2.jsonc
    markdownlint_exit_code="${?}"
    set -e
    rm -f .markdownlint-cli2.jsonc
    [[ "${markdownlint_exit_code}" -eq 0 ]] || exit "${markdownlint_exit_code}"
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
  uvx zizmor --fix=safe "${ZIZMOR_PATHS[@]}"
  N_WORKFLOW_YAML_FILES=$(git ls-files -- '.github/workflows/**.yml' '.github/workflows/**.yaml' | wc -l)
  if [[ "${N_WORKFLOW_YAML_FILES}" -gt 0 ]]; then
    git ls-files -z -- '.github/workflows/*.yml' '.github/workflows/*.yaml' \
      | xargs -0 -t actionlint
    git ls-files -z -- '.github/workflows/*.yml' '.github/workflows/*.yaml' \
      | xargs -0 -t uvx yamllint -d '{"extends": "relaxed", "rules": {"line-length": "disable"}}'
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
  uvx checkov --framework=all --output=github_failed_only --directory=.
fi
if [[ "${N_TERRAFORM_FILES}" -gt 0 ]] || [[ "${N_DOCKER_FILES}" -gt 0 ]]; then
  trivy filesystem --scanners vuln,secret,misconfig --skip-dirs .venv --skip-dirs .terraform --skip-dirs .terragrunt-cache --skip-dirs node_modules --skip-dirs .git .
fi
