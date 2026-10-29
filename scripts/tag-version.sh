#!/usr/bin/env bash
#
# Read the version from internal/server/server.go and, if no matching git tag
# exists yet, create an annotated tag vX.Y.Z (and push it when running in CI or
# with --push). Idempotent: a no-op when the tag already exists.
#
# Usage:
#   scripts/tag-version.sh          # create the tag locally; push only in CI
#   scripts/tag-version.sh --push   # also push the tag to origin
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

VERSION_FILE="internal/server/server.go"

version="$(grep -Eo 'const Version = "[0-9]+\.[0-9]+\.[0-9]+"' "$VERSION_FILE" \
  | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"

if [[ -z "$version" ]]; then
  echo "error: could not find 'const Version = \"x.y.z\"' in $VERSION_FILE" >&2
  exit 1
fi

tag="v${version}"

# Emit GitHub Actions step outputs (no-op locally).
emit() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  {
    echo "version=${version}"
    echo "tag=${tag}"
    echo "created=${1}"
  } >> "$GITHUB_OUTPUT"
}

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo "tag ${tag} already exists locally — nothing to do"
  emit false
  exit 0
fi

if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
  echo "tag ${tag} already exists on origin — nothing to do"
  emit false
  exit 0
fi

# CI runners have no git identity by default.
git config user.name  >/dev/null 2>&1 || git config user.name  "github-actions[bot]"
git config user.email >/dev/null 2>&1 || git config user.email "github-actions[bot]@users.noreply.github.com"

echo "creating tag ${tag}"
git tag -a "${tag}" -m "ami ${tag}"

if [[ "${1:-}" == "--push" || -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "pushing ${tag} to origin"
  git push origin "${tag}"
fi

emit true
echo "done: ${tag}"
