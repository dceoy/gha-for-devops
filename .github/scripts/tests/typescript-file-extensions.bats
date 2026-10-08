#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOWS=(
    typescript-package-format-and-pr.yml
    typescript-package-lint-and-scan.yml
  )
}

@test "TypeScript workflows cover ESM and CommonJS extensions" {
  for workflow in "${WORKFLOWS[@]}"; do
    workflow_file="${REPO_ROOT}/.github/workflows/${workflow}"
    for input in biome-glob prettier-glob; do
      glob="$(yq -r ".on.workflow_call.inputs.\"${input}\".default" "${workflow_file}")"
      [[ "${glob}" == *'{js,jsx,mjs,cjs,ts,tsx,mts,cts,'* ]]
    done
    grep -Fq 'eslint --ext .js,.jsx,.mjs,.cjs,.ts,.tsx,.mts,.cts ' "${workflow_file}"
  done
}

@test "Local QA detects and processes JS and TS module extensions" {
  qa="${REPO_ROOT}/.agents/skills/local-qa/scripts/qa.sh"
  grep -Fq "git ls-files -- '*.ts' '*.tsx' '*.mts' '*.cts'" "${qa}"
  grep -Fq "git ls-files -- '*.js' '*.jsx' '*.mjs' '*.cjs'" "${qa}"
  grep -Fq '{js,jsx,mjs,cjs,ts,tsx,mts,cts,' "${qa}"
  grep -Fq 'eslint --fix --ext .js,.jsx,.mjs,.cjs,.ts,.tsx,.mts,.cts ' "${qa}"
}
