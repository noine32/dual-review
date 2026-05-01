#!/usr/bin/env bash
set -euo pipefail

SKILL_DST="${CLAUDE_HOME:-$HOME/.claude}/skills/dual-review"

if [[ -L "$SKILL_DST" ]]; then
  rm "$SKILL_DST"
  echo "Removed symlink: $SKILL_DST"
elif [[ -e "$SKILL_DST" ]]; then
  echo "ERROR: $SKILL_DST is not a symlink. Skipping (manual removal required)." >&2
  exit 1
else
  echo "Nothing to remove at $SKILL_DST"
fi
