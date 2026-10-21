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
  MAIN_CURRENT=true
  if [[ "${head_sha}" != "${RELEASE_SHA}" ]]; then
    echo '::notice::main advanced since this workflow started; skipping this release.'
    MAIN_CURRENT=false
  fi
}

tag_is_publishable() {
  local tag="$1"
  local local_sha remote release
  if git show-ref --verify --quiet "refs/tags/${tag}"; then
    local_sha="$(git rev-parse "refs/tags/${tag}")"
    if [[ "${local_sha}" != "${RELEASE_SHA}" ]]; then
      echo "::error::Tag ${tag} already exists locally at a different object." >&2
      return 1
    fi
  fi
  # An API error is fatal; only an empty successful response means absent.
  remote="$(gh api "repos/${GITHUB_REPOSITORY}/git/matching-refs/tags/${tag}" \
    --jq ".[] | select(.ref == \"refs/tags/${tag}\") | [.object.type, .object.sha] | @tsv")"
  TAG_EXISTS=false
  if [[ -n "${remote}" ]]; then
    if [[ "${remote}" != "$(printf 'commit\t%s' "${RELEASE_SHA}")" ]]; then
      echo "::error::Tag ${tag} already exists remotely at a different object." >&2
      return 1
    fi
    # Recover only an orphan tag at this exact validated commit.
    release="$(gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate \
      --jq ".[] | select(.tag_name == \"${tag}\") | .id")"
    if [[ -n "${release}" ]]; then
      echo "::error::Release ${tag} already exists." >&2
      return 1
    fi
    TAG_EXISTS=true
  fi
}

case "${1:-}" in
  plan)
    # Only workflow files with workflow_call are part of the release surface.
    # Inspect both revisions so removals of reusable workflows are included.
    is_reusable_workflow() {
      local ref="$1"
      local path="$2"
      if ! git cat-file -e "${ref}:${path}" 2> /dev/null; then
        echo false
        return
      fi
      git show "${ref}:${path}" | yq -o=json '.on' | jq -r '
        if type == "object" then has("workflow_call")
        elif type == "array" then index("workflow_call") != null
        else . == "workflow_call" end
      '
    }

    reusable_workflows_changed() {
      local path old_reusable new_reusable
      WORKFLOWS_CHANGED=false
      while IFS= read -r -d '' path; do
        [[ "${path}" =~ ^\.github/workflows/[^/]+\.ya?ml$ ]] || continue
        old_reusable="$(is_reusable_workflow "${previous_tag}" "${path}")"
        new_reusable="$(is_reusable_workflow "${RELEASE_SHA}" "${path}")"
        if [[ "${old_reusable}" == true || "${new_reusable}" == true ]]; then
          WORKFLOWS_CHANGED=true
        fi
      done < <(git diff --no-renames --name-only -z "${previous_tag}" "${RELEASE_SHA}" -- .github/workflows)
    }

    main_is_current
    if [[ "${MAIN_CURRENT}" != true ]]; then
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

    case "${RELEASE_BUMP:-auto}" in
      major-release)
        major=$((major + 1))
        minor=0
        patch=0
        ;;
      minor-release)
        minor=$((minor + 1))
        patch=0
        ;;
      patch-release)
        patch=$((patch + 1))
        ;;
      auto)
        reusable_workflows_changed
        if [[ "${WORKFLOWS_CHANGED}" != true ]]; then
          echo '::notice::No changes to reusable workflows since the latest release.'
          echo 'sync-major=true' >> "${GITHUB_OUTPUT:?}"
          exit 0
        fi

        messages="$(git log --first-parent --format=%B "${previous_tag}..${RELEASE_SHA}")"
        # Squash-merge bodies can prefix subjects with "* "; trailers can be indented.
        # Breaking changes intentionally use a minor bump for this workflow library.
        if grep -Eq '^[[:space:]]*(\*[[:space:]]*)?[[:alnum:]_-]+(\([^)]*\))?!:|^[[:space:]]*(\*[[:space:]]*)?BREAKING[ -]CHANGE:' <<< "${messages}" \
          || grep -Eq '^[[:space:]]*(\*[[:space:]]*)?feat(\([^)]*\))?:' <<< "${messages}"; then
          minor=$((minor + 1))
          patch=0
        else
          patch=$((patch + 1))
        fi
        ;;
      *)
        echo "::error::Invalid release bump: ${RELEASE_BUMP}" >&2
        exit 2
        ;;
    esac
    tag="v${major}.${minor}.${patch}"
    tag_is_publishable "${tag}"
    if [[ "${TAG_EXISTS}" == true ]]; then
      echo "::notice::Resuming publication of ${tag} at ${RELEASE_SHA}."
    fi
    {
      echo 'ready=true'
      echo "tag=${tag}"
    } >> "${GITHUB_OUTPUT:?}"
    ;;
  publish)
    : "${RELEASE_TAG:?}"
    if [[ ! "${RELEASE_TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "::error::Invalid release tag: ${RELEASE_TAG}" >&2
      exit 1
    fi
    main_is_current
    if [[ "${MAIN_CURRENT}" != true ]]; then
      exit 0
    fi
    tag_is_publishable "${RELEASE_TAG}"
    # Creating the tag atomically first prevents --target from silently
    # publishing an existing tag that points to a different commit.
    if [[ "${TAG_EXISTS}" != true ]]; then
      gh api "repos/${GITHUB_REPOSITORY}/git/refs" --method POST \
        --field "ref=refs/tags/${RELEASE_TAG}" --field "sha=${RELEASE_SHA}" > /dev/null
    fi
    gh release create "${RELEASE_TAG}" --repo "${GITHUB_REPOSITORY}" \
      --verify-tag --title "${RELEASE_TAG}" --generate-notes
    echo 'published=true' >> "${GITHUB_OUTPUT:?}"
    ;;
  *)
    echo 'Usage: weekly-release.sh {plan|publish}' >&2
    exit 2
    ;;
esac
