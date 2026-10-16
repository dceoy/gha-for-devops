#!/usr/bin/env bash
set -euo pipefail

# Release only the main commit whose source is being validated by this run.
: "${GITHUB_REPOSITORY:?}"
: "${RELEASE_SHA:?}"
if [[ "${GITHUB_REF:-}" != 'refs/heads/main' ]]; then
  echo '::error::Weekly releases must run on refs/heads/main.' >&2
  exit 1
fi

main_is_current() {
  local head_sha
  head_sha="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/heads/main" --jq '.object.sha')"
  if [[ "${head_sha}" != "${RELEASE_SHA}" ]]; then
    echo '::notice::main advanced since this workflow started; skipping this release.'
    return 1
  fi
}

tag_is_absent() {
  local tag="$1"
  local remote
  if git show-ref --verify --quiet "refs/tags/${tag}"; then
    echo "::error::Tag ${tag} already exists locally." >&2
    return 1
  fi
  # An API error is fatal; an empty successful response means the tag is absent.
  remote="$(gh api "repos/${GITHUB_REPOSITORY}/git/matching-refs/tags/${tag}" \
    --jq ".[] | select(.ref == \"refs/tags/${tag}\") | .ref")"
  if [[ -n "${remote}" ]]; then
    echo "::error::Tag ${tag} already exists remotely." >&2
    return 1
  fi
}

case "${1:-}" in
  plan)
    if ! main_is_current; then
      exit 0
    fi

    previous_tag="$(gh release list --repo "${GITHUB_REPOSITORY}" \
      --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName')"
    if [[ ! "${previous_tag}" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
      echo "::error::Expected a latest stable SemVer release, got: ${previous_tag}" >&2
      exit 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
    if ! git merge-base --is-ancestor "${previous_tag}" "${RELEASE_SHA}"; then
      echo "::error::Release tag ${previous_tag} is not an ancestor of the release commit." >&2
      exit 1
    fi

    if git diff --quiet "${previous_tag}" "${RELEASE_SHA}" -- \
      .github/workflows .github/scripts .github/actions; then
      echo '::notice::No changes to reusable workflows or shared scripts since the latest release.'
      exit 0
    fi

    messages="$(git log --first-parent --format=%B "${previous_tag}..${RELEASE_SHA}")"
    # Squash-merge bodies can prefix subjects with "* "; trailers can be indented.
    if grep -Eq '^[[:space:]]*(\*[[:space:]]*)?[[:alnum:]_-]+(\([^)]*\))?!:|^[[:space:]]*(\*[[:space:]]*)?BREAKING[ -]CHANGE:' <<< "${messages}"; then
      echo '::error::Breaking changes require a reviewed manual major release.' >&2
      exit 1
    fi
    if grep -Eq '^[[:space:]]*(\*[[:space:]]*)?feat(\([^)]*\))?:' <<< "${messages}"; then
      minor=$((minor + 1))
      patch=0
    else
      patch=$((patch + 1))
    fi
    tag="v${major}.${minor}.${patch}"
    tag_is_absent "${tag}"
    {
      echo 'ready=true'
      echo "tag=${tag}"
      echo "sha=${RELEASE_SHA}"
    } >> "${GITHUB_OUTPUT:?}"
    ;;
  publish)
    : "${RELEASE_TAG:?}"
    if [[ ! "${RELEASE_TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "::error::Invalid release tag: ${RELEASE_TAG}" >&2
      exit 1
    fi
    if ! main_is_current; then
      exit 0
    fi
    tag_is_absent "${RELEASE_TAG}"
    # Creating the tag atomically first prevents --target from silently
    # publishing an existing tag that points to a different commit.
    gh api "repos/${GITHUB_REPOSITORY}/git/refs" --method POST \
      --field "ref=refs/tags/${RELEASE_TAG}" --field "sha=${RELEASE_SHA}" > /dev/null
    gh release create "${RELEASE_TAG}" --repo "${GITHUB_REPOSITORY}" \
      --verify-tag --title "${RELEASE_TAG}" --generate-notes
    echo 'published=true' >> "${GITHUB_OUTPUT:?}"
    ;;
  *)
    echo 'Usage: weekly-release.sh {plan|publish}' >&2
    exit 2
    ;;
esac
