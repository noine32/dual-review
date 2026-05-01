#!/usr/bin/env bash
# Invokes Codex CLI with mode-keyed model/reasoning presets.
#
# Usage: run-codex.sh <codex-mode> <prompt-file>
#
# codex-mode presets (ChatGPT Plus only supports gpt-5.2 — no -mini/-max):
#   review          gpt-5.2, reasoning=medium  (parallel reviewer, lighter)
#   plan-critique   gpt-5.2, reasoning=high    (plan critique R2)
#   critique        gpt-5.2, reasoning=high    (artifact critique R2)
#
# Env overrides: DUAL_MODEL, DUAL_REASONING, DUAL_TIMEOUT (default 300s)
#
# Exit codes:
#   0     success
#   64    usage error (bad args / unknown mode)
#   66    prompt file not found
#   124   codex timed out
#   127   codex CLI not in PATH
#   *     any other codex non-zero exit propagates

set -euo pipefail

readonly DEFAULT_TIMEOUT=300

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") <codex-mode> <prompt-file>

codex-mode:
  review          gpt-5.2 reasoning=medium
  plan-critique   gpt-5.2 reasoning=high
  critique        gpt-5.2 reasoning=high

Env overrides: DUAL_MODEL, DUAL_REASONING, DUAL_TIMEOUT (default ${DEFAULT_TIMEOUT}s)
EOF
}

if [[ $# -ne 2 ]]; then
  usage
  exit 64
fi

CODEX_MODE="$1"
PROMPT_FILE="$2"

case "$CODEX_MODE" in
  review)
    MODEL="gpt-5.2"
    REASONING="medium"
    ;;
  plan-critique|critique)
    MODEL="gpt-5.2"
    REASONING="high"
    ;;
  *)
    echo "ERROR: unknown codex-mode: $CODEX_MODE" >&2
    usage
    exit 64
    ;;
esac

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "ERROR: prompt file not found: $PROMPT_FILE" >&2
  exit 66
fi

MODEL="${DUAL_MODEL:-$MODEL}"
REASONING="${DUAL_REASONING:-$REASONING}"
TIMEOUT="${DUAL_TIMEOUT:-$DEFAULT_TIMEOUT}"

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || (( TIMEOUT < 1 || TIMEOUT > 3600 )); then
  echo "ERROR: DUAL_TIMEOUT must be an integer between 1 and 3600 (got: '$TIMEOUT')" >&2
  exit 64
fi

case "$REASONING" in
  low|medium|high) ;;
  *)
    echo "ERROR: DUAL_REASONING must be one of: low, medium, high (got: '$REASONING')" >&2
    exit 64
    ;;
esac

# MODEL: reject empty/whitespace-only values; allow the actual model name to pass through.
if [[ -z "${MODEL// }" ]]; then
  echo "ERROR: DUAL_MODEL must not be empty or whitespace-only" >&2
  exit 64
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex CLI not found in PATH" >&2
  exit 127
fi

# mktemp -t is GNU/BSD-different; use explicit template under TMPDIR for portability.
STDERR_FILE="$(mktemp "${TMPDIR:-/tmp}/dual-codex-err.XXXXXX")"
trap 'rm -f -- "$STDERR_FILE"' EXIT

# Detect timeout binary (GNU coreutils on Linux; gtimeout on macOS via brew).
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi

set +e
if [[ -n "$TIMEOUT_BIN" ]]; then
  "$TIMEOUT_BIN" --foreground "${TIMEOUT}s" \
    codex exec \
      --skip-git-repo-check \
      --sandbox read-only \
      -m "$MODEL" \
      --config "model_reasoning_effort=\"${REASONING}\"" \
      < "$PROMPT_FILE" \
      2>"$STDERR_FILE"
  RC=$?
else
  echo "Warning: timeout/gtimeout not found; running codex without timeout" >&2
  codex exec \
    --skip-git-repo-check \
    --sandbox read-only \
    -m "$MODEL" \
    --config "model_reasoning_effort=\"${REASONING}\"" \
    < "$PROMPT_FILE" \
    2>"$STDERR_FILE"
  RC=$?
fi
set -e

if [[ $RC -ne 0 ]]; then
  # Only label 124 as timeout when timeout binary was actually used.
  # Otherwise, codex itself may have returned 124 for unrelated reasons.
  if [[ $RC -eq 124 && -n "$TIMEOUT_BIN" ]]; then
    echo "ERROR: codex timed out after ${TIMEOUT}s" >&2
  fi
  if [[ -s "$STDERR_FILE" ]]; then
    echo "--- codex stderr (last 50 lines) ---" >&2
    tail -n 50 "$STDERR_FILE" >&2
  fi
fi
exit "$RC"
