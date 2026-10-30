#!/usr/bin/env bash
#
# Bump the version across its two surfaces:
#   - internal/server/server.go  (const Version — the source of truth)
#   - README.md                  (the "Status … (vX.Y.Z)" badge)
#
# Reads the current version, shows it, and asks whether to bump the major,
# minor, or patch component. Writes both files so scripts/check-version.sh
# stays happy. Does not commit or tag — that's left to you (and tag-version.sh).
#
# Usage:
#   scripts/bump-version.sh            # interactive: pick major/minor/patch
#   scripts/bump-version.sh major      # non-interactive bump
#   scripts/bump-version.sh minor
#   scripts/bump-version.sh patch
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/bump-version.sh [major|minor|patch]

Bump the version across its two surfaces:
  - internal/server/server.go  (const Version — the source of truth)
  - README.md                  (the "Status … (vX.Y.Z)" badge)

With no argument, prompts interactively to pick major/minor/patch.
Does not commit or tag — that's left to you (and tag-version.sh).

Options:
  -h, --help    Show this help message and exit
EOF
}

case "${1:-}" in
  -h | --help | help | usage)
    usage
    exit 0
    ;;
esac

cd "$(git rev-parse --show-toplevel)"

VERSION_FILE="internal/server/server.go"
README="README.md"

current="$(grep -Eo 'const Version = "[0-9]+\.[0-9]+\.[0-9]+"' "$VERSION_FILE" \
  | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"

if [[ -z "$current" ]]; then
  echo "error: could not find 'const Version = \"x.y.z\"' in $VERSION_FILE" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<< "$current"

echo "Current version: $current"

part="${1:-}"
if [[ -z "$part" ]]; then
  echo
  echo "Select bump type:"
  echo "  1) major  ($major.$minor.$patch -> $((major + 1)).0.0)"
  echo "  2) minor  ($major.$minor.$patch -> $major.$((minor + 1)).0)"
  echo "  3) patch  ($major.$minor.$patch -> $major.$minor.$((patch + 1)))"
  echo
  read -r -p "Choice [1/2/3 or major/minor/patch]: " choice
  case "$choice" in
    1 | major) part="major" ;;
    2 | minor) part="minor" ;;
    3 | patch) part="patch" ;;
    *)
      echo "error: invalid choice '$choice'" >&2
      exit 1
      ;;
  esac
fi

case "$part" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *)
    echo "error: unknown bump type '$part' (want major, minor, or patch)" >&2
    exit 1
    ;;
esac

new="${major}.${minor}.${patch}"

# Portable in-place edit (BSD/macOS sed needs an arg to -i; GNU doesn't).
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

sed_inplace -E "s/const Version = \"${current}\"/const Version = \"${new}\"/" "$VERSION_FILE"
sed_inplace -E "s/\(v${current}\)/(v${new}\)/" "$README"

echo "Bumped: $current -> $new"
echo "  $VERSION_FILE"
echo "  $README"

# Sanity-check the two surfaces now agree, if the checker is present.
if [[ -x scripts/check-version.sh ]]; then
  scripts/check-version.sh
fi
