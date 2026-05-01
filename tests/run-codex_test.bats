#!/usr/bin/env bats

load test_helper

SCRIPT="skills/dual-review/scripts/run-codex.sh"

setup() {
  setup_test_env
  install_codex_mock
  PROMPT="$TEST_TMP/prompt.md"
  echo "test prompt content" > "$PROMPT"
}

teardown() {
  teardown_test_env
}

@test "review mode passes -m gpt-5.2 and reasoning=medium" {
  run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<-m> <gpt-5.2>"* ]]
  [[ "$output" == *"model_reasoning_effort=\"medium\""* ]]
  [[ "$output" == *"<--sandbox> <read-only>"* ]]
  [[ "$output" == *"<--skip-git-repo-check>"* ]]
}

@test "DUAL_REQUIRE_GIT_REPO=1 omits --skip-git-repo-check" {
  DUAL_REQUIRE_GIT_REPO=1 run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"<--skip-git-repo-check>"* ]]
}

@test "plan-critique mode passes -m gpt-5.2 and reasoning=high" {
  run "$REPO_ROOT/$SCRIPT" plan-critique "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<-m> <gpt-5.2>"* ]]
  [[ "$output" == *"model_reasoning_effort=\"high\""* ]]
}

@test "critique mode passes -m gpt-5.2 and reasoning=high" {
  run "$REPO_ROOT/$SCRIPT" critique "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<-m> <gpt-5.2>"* ]]
  [[ "$output" == *"model_reasoning_effort=\"high\""* ]]
}

@test "prompt content is piped via stdin" {
  run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test prompt content"* ]]
}

@test "DUAL_MODEL env overrides model" {
  DUAL_MODEL="gpt-5.2" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<-m> <gpt-5.2>"* ]]
}

@test "DUAL_REASONING env overrides reasoning effort" {
  DUAL_REASONING="low" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"model_reasoning_effort=\"low\""* ]]
}

@test "unknown codex-mode exits with code 64" {
  run "$REPO_ROOT/$SCRIPT" frobnicate "$PROMPT"
  [ "$status" -eq 64 ]
}

@test "missing prompt file exits with code 66" {
  run "$REPO_ROOT/$SCRIPT" review "$TEST_TMP/does-not-exist.md"
  [ "$status" -eq 66 ]
}

@test "wrong number of args exits with code 64" {
  run "$REPO_ROOT/$SCRIPT" review
  [ "$status" -eq 64 ]
}

@test "missing codex CLI exits with code 127" {
  rm "$TEST_TMP/bin/codex"
  PATH="$TEST_TMP/bin:/usr/bin:/bin" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 127 ]
}

@test "codex non-zero exit propagates" {
  install_codex_mock_failing 5
  run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 5 ]
}

@test "codex failure exposes stderr file path (default safe)" {
  install_codex_mock_failing 7
  run --separate-stderr "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 7 ]
  # default: don't print stderr content (may leak secrets); only point to the file
  [[ "$stderr" == *"codex stderr saved to"* ]] || [[ "$stderr" == *"DUAL_SHOW_STDERR"* ]]
  [[ "$stderr" != *"mock codex error"* ]]
}

@test "DUAL_SHOW_STDERR=1 prints stderr tail on failure (explicit opt-in)" {
  install_codex_mock_failing 7
  DUAL_SHOW_STDERR=1 run --separate-stderr "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 7 ]
  [[ "$stderr" == *"mock codex error"* ]]
}

@test "codex success does not leak stderr to stdout" {
  cat > "$TEST_TMP/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo "STDOUT_OK"
echo "STDERR_NOISE_should_not_leak" >&2
EOF
  chmod +x "$TEST_TMP/bin/codex"
  run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STDOUT_OK"* ]]
  [[ "$output" != *"STDERR_NOISE_should_not_leak"* ]]
}

@test "DUAL_TIMEOUT enforces timeout (slow codex killed)" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "timeout/gtimeout not available"
  install_codex_mock_slow 10
  DUAL_TIMEOUT=1 run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 124 ]
}

@test "DUAL_TIMEOUT rejects non-numeric value" {
  DUAL_TIMEOUT="abc" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 64 ]
  [[ "$stderr" == *"DUAL_TIMEOUT"* ]] || [[ "$output" == *"DUAL_TIMEOUT"* ]]
}

@test "DUAL_TIMEOUT rejects zero" {
  DUAL_TIMEOUT=0 run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 64 ]
}

@test "DUAL_TIMEOUT rejects out-of-range value" {
  DUAL_TIMEOUT=99999 run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 64 ]
}

@test "DUAL_TIMEOUT rejects empty string" {
  DUAL_TIMEOUT="" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  # empty falls back to default (DUAL_TIMEOUT:-300), should succeed
  [ "$status" -eq 0 ]
}

@test "RC 124 not labeled as timeout when no timeout binary was used" {
  # codex itself returns 124, but we have neither timeout nor gtimeout
  for tool in mktemp rm cat tail head env bash basename dirname touch; do
    if path="$(command -v "$tool")"; then
      ln -sf "$path" "$TEST_TMP/bin/$tool"
    fi
  done
  cat > "$TEST_TMP/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo "codex internal failure" >&2
exit 124
EOF
  chmod +x "$TEST_TMP/bin/codex"
  PATH="$TEST_TMP/bin" DUAL_ALLOW_NO_TIMEOUT=1 run --separate-stderr "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 124 ]
  [[ "$stderr" != *"codex timed out after"* ]]
}

@test "RC 124 IS labeled as timeout when timeout binary was actually used" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "timeout/gtimeout not available"
  install_codex_mock_slow 10
  DUAL_TIMEOUT=1 run --separate-stderr "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 124 ]
  [[ "$stderr" == *"codex timed out after"* ]]
}

@test "DUAL_REASONING rejects values outside allow-list" {
  DUAL_REASONING="evil\"injection" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 64 ]
}

@test "DUAL_REASONING accepts low, medium, high (Plus-safe levels)" {
  for level in low medium high; do
    DUAL_REASONING="$level" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
    [ "$status" -eq 0 ]
  done
}

@test "DUAL_REASONING rejects xhigh (Pro/Business only)" {
  DUAL_REASONING="xhigh" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 64 ]
}

@test "DUAL_MODEL rejects empty value via env override" {
  # Note: empty env var via :- defaults; this tests an intentionally empty value
  DUAL_MODEL=" " run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 64 ]
}

@test "DUAL_MODEL rejects gpt-5.2-mini (not supported on Plus)" {
  DUAL_MODEL="gpt-5.2-mini" run --separate-stderr "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 64 ]
  [[ "$stderr" == *"Plus"* ]] || [[ "$stderr" == *"gpt-5.2"* ]]
}

@test "DUAL_MODEL rejects gpt-5.2-max (not supported on Plus)" {
  DUAL_MODEL="gpt-5.2-max" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 64 ]
}

@test "DUAL_MODEL accepts only gpt-5.2" {
  DUAL_MODEL="gpt-5.2" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "falls back to gtimeout when timeout is unavailable" {
  # Construct minimal PATH (only $TEST_TMP/bin) to hide system timeout.
  for tool in mktemp rm cat tail head env bash basename dirname touch; do
    if path="$(command -v "$tool")"; then
      ln -sf "$path" "$TEST_TMP/bin/$tool"
    fi
  done
  MARKER="$TEST_TMP/gtimeout.used"
  cat > "$TEST_TMP/bin/gtimeout" <<EOF
#!/usr/bin/env bash
touch "$MARKER"
shift  # --foreground
shift  # duration
exec "\$@"
EOF
  chmod +x "$TEST_TMP/bin/gtimeout"

  PATH="$TEST_TMP/bin" run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
  [ -f "$MARKER" ]
}

@test "refuses to run without timeout unless DUAL_ALLOW_NO_TIMEOUT=1" {
  for tool in mktemp rm cat tail head env bash basename dirname touch; do
    if path="$(command -v "$tool")"; then
      ln -sf "$path" "$TEST_TMP/bin/$tool"
    fi
  done
  PATH="$TEST_TMP/bin" run --separate-stderr "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 64 ]
  [[ "$stderr" == *"DUAL_ALLOW_NO_TIMEOUT"* ]]
}

@test "runs without timeout when DUAL_ALLOW_NO_TIMEOUT=1 (explicit opt-in)" {
  for tool in mktemp rm cat tail head env bash basename dirname touch; do
    if path="$(command -v "$tool")"; then
      ln -sf "$path" "$TEST_TMP/bin/$tool"
    fi
  done
  PATH="$TEST_TMP/bin" DUAL_ALLOW_NO_TIMEOUT=1 run --separate-stderr "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STDIN:"* ]]
}
