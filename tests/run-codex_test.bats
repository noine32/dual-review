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

@test "review mode passes -m gpt-5.2-mini and reasoning=medium" {
  run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<-m> <gpt-5.2-mini>"* ]]
  [[ "$output" == *"model_reasoning_effort=\"medium\""* ]]
  [[ "$output" == *"<--sandbox> <read-only>"* ]]
  [[ "$output" == *"<--skip-git-repo-check>"* ]]
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
  DUAL_MODEL="gpt-5.2-mini" run "$REPO_ROOT/$SCRIPT" critique "$PROMPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<-m> <gpt-5.2-mini>"* ]]
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

@test "DUAL_TIMEOUT enforces timeout (slow codex killed)" {
  install_codex_mock_slow 10
  DUAL_TIMEOUT=1 run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
  [ "$status" -eq 124 ]
}
