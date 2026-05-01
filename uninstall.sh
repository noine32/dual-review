#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${CLAUDE_HOME:-}" ]]; then
  if [[ -z "${HOME:-}" ]]; then
    echo "ERROR: neither CLAUDE_HOME nor HOME is set; cannot determine install destination" >&2
    exit 1
  fi
  CLAUDE_HOME="$HOME/.claude"
fi
SKILL_DST="$CLAUDE_HOME/skills/dual-review"

# Defensive: refuse paths starting with `-` (we don't use `--` for BSD compatibility).
case "$SKILL_DST" in -*) echo "ERROR: SKILL_DST must not start with '-': $SKILL_DST" >&2; exit 1;; esac

if [[ -L "$SKILL_DST" ]]; then
  rm -f "$SKILL_DST"
  echo "Removed symlink: $SKILL_DST"
elif [[ -e "$SKILL_DST" ]]; then
  echo "ERROR: $SKILL_DST is not a symlink. Skipping (manual removal required)." >&2
  exit 1
else
  echo "Nothing to remove at $SKILL_DST"
fi
