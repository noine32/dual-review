#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/dual-review"
SKILL_DST="${CLAUDE_HOME:-$HOME/.claude}/skills/dual-review"

if [[ ! -d "$SKILL_SRC" ]]; then
  echo "ERROR: skill source missing: $SKILL_SRC" >&2
  exit 1
fi

mkdir -p "$(dirname "$SKILL_DST")"

if [[ -L "$SKILL_DST" ]]; then
  echo "Removing old symlink: $SKILL_DST"
  rm "$SKILL_DST"
elif [[ -e "$SKILL_DST" ]]; then
  BACKUP="${SKILL_DST}.bak.$(date +%s)"
  echo "Backing up existing dir to: $BACKUP"
  mv "$SKILL_DST" "$BACKUP"
fi

ln -s "$SKILL_SRC" "$SKILL_DST"
echo "Installed: $SKILL_DST -> $SKILL_SRC"

if ! command -v codex >/dev/null 2>&1; then
  echo "Warning: codex CLI not found in PATH. Install Codex CLI >= 0.57." >&2
fi
