#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  # install.sh expects skills/dual-review/ to exist at REPO_ROOT
  mkdir -p "$REPO_ROOT/skills/dual-review"
}

teardown() {
  teardown_test_env
}

@test "install creates symlink under \$CLAUDE_HOME/skills/" {
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$CLAUDE_HOME/skills/dual-review" ]
  target="$(readlink "$CLAUDE_HOME/skills/dual-review")"
  [ "$target" = "$REPO_ROOT/skills/dual-review" ]
}

@test "install is idempotent (re-running replaces existing symlink)" {
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$CLAUDE_HOME/skills/dual-review" ]
}

@test "install backs up existing real directory" {
  mkdir -p "$CLAUDE_HOME/skills/dual-review"
  echo "old content" > "$CLAUDE_HOME/skills/dual-review/old.txt"
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$CLAUDE_HOME/skills/dual-review" ]
  shopt -s nullglob
  backups=("$CLAUDE_HOME/skills/dual-review.bak."*)
  [ "${#backups[@]}" -eq 1 ]
  [ -f "${backups[0]}/old.txt" ]
}

@test "install fails clearly if skill source is missing" {
  # Copy install.sh into an isolated dir without skills/
  cp "$REPO_ROOT/install.sh" "$TEST_TMP/install.sh"
  chmod +x "$TEST_TMP/install.sh"
  run "$TEST_TMP/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"skill source missing"* ]]
}

@test "uninstall removes symlink" {
  "$REPO_ROOT/install.sh"
  [ -L "$CLAUDE_HOME/skills/dual-review" ]
  run "$REPO_ROOT/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_HOME/skills/dual-review" ]
}

@test "uninstall is no-op when nothing installed" {
  run "$REPO_ROOT/uninstall.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to remove"* ]]
}

@test "uninstall refuses to remove non-symlink directory" {
  mkdir -p "$CLAUDE_HOME/skills/dual-review"
  echo "user content" > "$CLAUDE_HOME/skills/dual-review/keep.txt"
  run "$REPO_ROOT/uninstall.sh"
  [ "$status" -ne 0 ]
  [ -d "$CLAUDE_HOME/skills/dual-review" ]
  [ -f "$CLAUDE_HOME/skills/dual-review/keep.txt" ]
}

@test "install fails clearly when HOME and CLAUDE_HOME are both unset" {
  run env -i PATH="$PATH" bash "$REPO_ROOT/install.sh"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"HOME"* ]] || [[ "$output" == *"HOME"* ]]
}

@test "install respects CLAUDE_HOME even when HOME is unset" {
  # CLAUDE_HOME is set, HOME is unset → must succeed
  run env -i PATH="$PATH" CLAUDE_HOME="$CLAUDE_HOME" bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$CLAUDE_HOME/skills/dual-review" ]
}

@test "install creates unique backup names even within the same second" {
  # First backup: real dir
  mkdir -p "$CLAUDE_HOME/skills/dual-review"
  echo "v1" > "$CLAUDE_HOME/skills/dual-review/file.txt"
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  shopt -s nullglob
  backups_after_first=("$CLAUDE_HOME/skills/dual-review.bak."*)
  [ "${#backups_after_first[@]}" -eq 1 ]

  # Second: replace symlink with another real dir, install again immediately
  rm "$CLAUDE_HOME/skills/dual-review"
  mkdir -p "$CLAUDE_HOME/skills/dual-review"
  echo "v2" > "$CLAUDE_HOME/skills/dual-review/file.txt"
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  backups_after_second=("$CLAUDE_HOME/skills/dual-review.bak."*)
  # We expect 2 distinct backups (no collision -> mv didn't fail)
  [ "${#backups_after_second[@]}" -eq 2 ]
}

@test "install backs up regular file (not just dir)" {
  # rare case: SKILL_DST is a regular file
  mkdir -p "$CLAUDE_HOME/skills"
  echo "stray file" > "$CLAUDE_HOME/skills/dual-review"
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$CLAUDE_HOME/skills/dual-review" ]
  shopt -s nullglob
  backups=("$CLAUDE_HOME/skills/dual-review.bak."*)
  [ "${#backups[@]}" -eq 1 ]
  [ -f "${backups[0]}" ]
}

@test "install handles CLAUDE_HOME with spaces in path" {
  SPACE_HOME="$TEST_TMP/has space/.claude"
  run env CLAUDE_HOME="$SPACE_HOME" "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$SPACE_HOME/skills/dual-review" ]
}
