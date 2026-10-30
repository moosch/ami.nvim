#!/usr/bin/env bash
#
# Bump the version across its two surfaces:
#   - VERSION    (the source of truth)
#   - README.md  (the "Status … (vX.Y.Z)" badge)
#
# Usage:
#   scripts/bump-version.sh            # interactive: pick major/minor/patch
#   scripts/bump-version.sh major|minor|patch
set -euo pipefail

case "${1:-}" in
  -h | --help | help)
    echo "Usage: scripts/bump-version.sh [major|minor|patch]"
    exit 0
    ;;
esac

cd "$(git rev-parse --show-toplevel)"

VERSION_FILE="VERSION"
README="README.md"

current="$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)"
if [[ ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: $VERSION_FILE missing or not X.Y.Z (got '${current}')" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<< "$current"
echo "Current version: $current"

part="${1:-}"
if [[ -z "$part" ]]; then
  echo
  echo "  1) major  ($current -> $((major + 1)).0.0)"
  echo "  2) minor  ($current -> $major.$((minor + 1)).0)"
  echo "  3) patch  ($current -> $major.$minor.$((patch + 1)))"
  read -r -p "Choice [1/2/3 or major/minor/patch]: " choice
  case "$choice" in
    1 | major) part="major" ;;
    2 | minor) part="minor" ;;
    3 | patch) part="patch" ;;
    *) echo "error: invalid choice '$choice'" >&2; exit 1 ;;
  esac
fi

case "$part" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *) echo "error: unknown bump type '$part'" >&2; exit 1 ;;
esac

new="${major}.${minor}.${patch}"

printf '%s\n' "$new" > "$VERSION_FILE"

sed_inplace() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi
}
sed_inplace -E "s/\(v${current}\)/(v${new})/" "$README"

echo "Bumped: $current -> $new"
echo "  $VERSION_FILE"
echo "  $README"

if [[ -x scripts/check-version.sh ]]; then
  scripts/check-version.sh
fi
