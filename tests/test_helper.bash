#!/usr/bin/env bash
# Shared bats setup. Source via `load test_helper` (file extension omitted).

# REPO_ROOT: absolute path to repo root (one above tests/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# setup_test_env: create isolated tmp dir + mock codex on PATH.
# Sets TEST_TMP, CLAUDE_HOME, and prepends $TEST_TMP/bin to PATH.
setup_test_env() {
  # mktemp -t differs between GNU/BSD; use explicit template under TMPDIR for portability.
  TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dualrev.XXXXXX")"
  export TEST_TMP
  export CLAUDE_HOME="$TEST_TMP/.claude"
  mkdir -p "$TEST_TMP/bin"
  export PATH="$TEST_TMP/bin:$PATH"
}

# teardown_test_env: clean up tmp dir.
teardown_test_env() {
  [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# install_codex_mock: mock codex that prints args + stdin to stdout.
install_codex_mock() {
  cat > "$TEST_TMP/bin/codex" <<'MOCK_EOF'
#!/usr/bin/env bash
printf "ARGS:"
for a in "$@"; do printf " <%s>" "$a"; done
printf "\nSTDIN:\n"
cat -
MOCK_EOF
  chmod +x "$TEST_TMP/bin/codex"
}

# install_codex_mock_failing: mock codex that exits with given code.
install_codex_mock_failing() {
  local exit_code="${1:-1}"
  cat > "$TEST_TMP/bin/codex" <<MOCK_EOF
#!/usr/bin/env bash
echo "mock codex error" >&2
exit ${exit_code}
MOCK_EOF
  chmod +x "$TEST_TMP/bin/codex"
}

# install_codex_mock_slow: mock codex that sleeps N seconds before exiting.
install_codex_mock_slow() {
  local sleep_seconds="${1:-10}"
  cat > "$TEST_TMP/bin/codex" <<MOCK_EOF
#!/usr/bin/env bash
sleep ${sleep_seconds}
echo "should not reach here"
MOCK_EOF
  chmod +x "$TEST_TMP/bin/codex"
}
