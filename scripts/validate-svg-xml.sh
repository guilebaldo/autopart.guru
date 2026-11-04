#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
shopt -s nullglob
failed=0
for f in "$root"/assets/*.svg; do
  if ! xmllint --noout "$f" 2>/dev/null; then
    echo "INVALID: $f" >&2
    xmllint --noout "$f" || true
    failed=1
  else
    echo "OK: $f"
  fi
done
exit "$failed"
