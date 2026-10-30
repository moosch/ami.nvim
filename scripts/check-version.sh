#!/usr/bin/env bash
#
# Verify the version is consistent across its two surfaces:
#   - VERSION    (the source of truth CI tags from)
#   - README.md  (the "Status … (vX.Y.Z)" badge)
#
# Fails (non-zero) if they drift, so a forgotten README bump can't ship.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

VERSION_FILE="VERSION"
README="README.md"

version="$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: $VERSION_FILE missing or not X.Y.Z (got '${version}')" >&2
  exit 1
fi

readme_version="$(grep -Eo '\(v[0-9]+\.[0-9]+\.[0-9]+\)' "$README" \
  | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [[ -z "$readme_version" ]]; then
  echo "error: could not find a '(vX.Y.Z)' status badge in $README" >&2
  exit 1
fi

if [[ "$version" != "$readme_version" ]]; then
  cat >&2 <<EOF
error: version mismatch
  $VERSION_FILE : $version
  $README       : $readme_version
Update the README status badge to match VERSION (the source of truth).
EOF
  exit 1
fi

echo "version OK: $version (VERSION == README)"
