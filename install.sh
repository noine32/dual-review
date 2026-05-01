#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_SRC="$SCRIPT_DIR/skills/dual-review"

if [[ -z "${CLAUDE_HOME:-}" ]]; then
  if [[ -z "${HOME:-}" ]]; then
    echo "ERROR: neither CLAUDE_HOME nor HOME is set; cannot determine install destination" >&2
    exit 1
  fi
  CLAUDE_HOME="$HOME/.claude"
fi
SKILL_DST="$CLAUDE_HOME/skills/dual-review"

if [[ ! -d "$SKILL_SRC" ]]; then
  echo "ERROR: skill source missing: $SKILL_SRC" >&2
  exit 1
fi

# Defensive: refuse paths starting with `-` to prevent option injection
# (we removed `--` from `ln -s` for BSD/macOS compatibility).
case "$SKILL_SRC" in -*) echo "ERROR: SKILL_SRC must not start with '-': $SKILL_SRC" >&2; exit 1;; esac
case "$SKILL_DST" in -*) echo "ERROR: SKILL_DST must not start with '-': $SKILL_DST" >&2; exit 1;; esac

mkdir -p "$(dirname "$SKILL_DST")"

if [[ -L "$SKILL_DST" ]]; then
  # readlink lacks `--` on BSD/macOS; use without it.
  link_target="$(readlink "$SKILL_DST" 2>/dev/null || true)"
  echo "Removing old symlink: $SKILL_DST${link_target:+ -> $link_target}"
  rm -- "$SKILL_DST"
elif [[ -e "$SKILL_DST" ]]; then
  # Use date+pid+random to avoid collisions when run concurrently or in same second.
  BACKUP="${SKILL_DST}.bak.$(date +%s).$$.${RANDOM}"
  echo "Backing up existing path to: $BACKUP"
  mv -- "$SKILL_DST" "$BACKUP"
fi

# `ln -s --` is not portable to BSD/macOS; rely on path-starts-with-dash guard above.
ln -s "$SKILL_SRC" "$SKILL_DST"
echo "Installed: $SKILL_DST -> $SKILL_SRC"

if ! command -v codex >/dev/null 2>&1; then
  echo "Warning: codex CLI not found in PATH. Install Codex CLI >= 0.57." >&2
fi
