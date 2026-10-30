#!/usr/bin/env bash
#
# Verify the version is consistent across its two surfaces:
#   - internal/server/server.go  (const Version — the source of truth CI tags from)
#   - README.md                  (the "Status … (vX.Y.Z)" badge)
#
# Fails (non-zero) if they drift, so a forgotten README bump can't ship.
#
# Usage: scripts/check-version.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

VERSION_FILE="internal/server/server.go"
README="README.md"

go_version="$(grep -Eo 'const Version = "[0-9]+\.[0-9]+\.[0-9]+"' "$VERSION_FILE" \
  | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"

if [[ -z "$go_version" ]]; then
  echo "error: could not find 'const Version = \"x.y.z\"' in $VERSION_FILE" >&2
  exit 1
fi

readme_version="$(grep -Eo '\(v[0-9]+\.[0-9]+\.[0-9]+\)' "$README" \
  | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"

if [[ -z "$readme_version" ]]; then
  echo "error: could not find a '(vX.Y.Z)' status badge in $README" >&2
  exit 1
fi

if [[ "$go_version" != "$readme_version" ]]; then
  cat >&2 <<EOF
error: version mismatch
  $VERSION_FILE : $go_version
  $README       : $readme_version
Update the README status badge to match the Go const (the source of truth).
EOF
  exit 1
fi

echo "version OK: $go_version (server.go == README)"
