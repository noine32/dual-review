#!/usr/bin/env bash
# Invokes Codex CLI with mode-keyed model/reasoning presets.
#
# Usage: run-codex.sh <codex-mode> <prompt-file>
#
# codex-mode presets:
#   review          gpt-5.2-mini, reasoning=medium  (parallel reviewer)
#   plan-critique   gpt-5.2,      reasoning=high    (plan critique R2)
#   critique        gpt-5.2,      reasoning=high    (artifact critique R2)
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
  review          gpt-5.2-mini reasoning=medium
  plan-critique   gpt-5.2      reasoning=high
  critique        gpt-5.2      reasoning=high

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
    MODEL="gpt-5.2-mini"
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

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex CLI not found in PATH" >&2
  exit 127
fi

set +e
timeout --foreground "${TIMEOUT}s" \
  codex exec \
    --skip-git-repo-check \
    --sandbox read-only \
    -m "$MODEL" \
    --config "model_reasoning_effort=\"${REASONING}\"" \
    < "$PROMPT_FILE" \
    2>/dev/null
RC=$?
set -e

if [[ $RC -eq 124 ]]; then
  echo "ERROR: codex timed out after ${TIMEOUT}s" >&2
fi
exit $RC
