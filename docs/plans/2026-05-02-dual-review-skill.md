# dual-review Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code skill (`dual-review`) that orchestrates Claude + Codex (ChatGPT Plus) to co-review code, brainstorm/critique plans, and adversarially critique Claude's outputs. Distribute as a self-installable git repo.

**Architecture:** Bash-based skill: `SKILL.md` defines triggers and orchestration prose; `scripts/run-codex.sh` is the single Codex invocation point with mode-keyed model/reasoning presets; `prompts/*.md` are templates Claude renders before piping to Codex via stdin. `install.sh` symlinks `skills/dual-review/` into `~/.claude/skills/`. Tests are bats-based with mocked `codex`.

**Tech Stack:** Bash 5.x, GNU coreutils (`timeout`), bats-core (test runner), git, Codex CLI ≥ 0.57.

**Spec:** [`docs/design.md`](../design.md)

---

## File Structure

| Path | Purpose |
|---|---|
| `LICENSE` | MIT |
| `.gitignore` | Ignore `node_modules/`, `tmp/`, OS files |
| `README.md` | User-facing: install, usage, triggers, troubleshoot |
| `install.sh` | Symlink `skills/dual-review` into `$CLAUDE_HOME/skills/` |
| `uninstall.sh` | Remove symlink |
| `skills/dual-review/SKILL.md` | Skill frontmatter + body (Claude-facing prose) |
| `skills/dual-review/scripts/run-codex.sh` | Codex invocation helper (mode → model/reasoning) |
| `skills/dual-review/prompts/review-codex.md` | Codex prompt for `review` mode |
| `skills/dual-review/prompts/plan-critique.md` | Codex prompt for `plan` mode R2 |
| `skills/dual-review/prompts/critique.md` | Codex prompt for `critique` mode R2 |
| `tests/test_helper.bash` | Shared bats setup: codex mock, tmp dir |
| `tests/install_test.bats` | Install/uninstall behavior |
| `tests/run-codex_test.bats` | Mode → flag mapping, env override, errors |
| `package.json` | Dev dep: `bats` (npm) + `npm test` script |

Design boundaries:
- `run-codex.sh` is the **only** place that knows Codex flag syntax. SKILL.md never embeds raw `codex exec` commands.
- Prompts live in `.md` files, not bash heredocs — easy to edit, lint, version.
- Test mocks PATH-shadow `codex`; the real Codex CLI is never called from tests.

---

### Task 1: Bootstrap repo (LICENSE, .gitignore, package.json)

**Files:**
- Create: `/home/noine/dual-review/LICENSE`
- Create: `/home/noine/dual-review/.gitignore`
- Create: `/home/noine/dual-review/package.json`

- [ ] **Step 1: Create LICENSE (MIT)**

Write `/home/noine/dual-review/LICENSE`:

```
MIT License

Copyright (c) 2026 noine32

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Create .gitignore**

Write `/home/noine/dual-review/.gitignore`:

```
node_modules/
tmp/
.DS_Store
*.bak.*
*.log
```

- [ ] **Step 3: Create package.json**

Write `/home/noine/dual-review/package.json`:

```json
{
  "name": "dual-review",
  "version": "0.1.0",
  "description": "Claude Code skill for dual-AI (Claude + Codex) code review, planning, and critique",
  "private": true,
  "scripts": {
    "test": "bats tests/"
  },
  "devDependencies": {
    "bats": "^1.11.0"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/noine32/dual-review.git"
  },
  "license": "MIT"
}
```

- [ ] **Step 4: Install bats**

Run: `cd /home/noine/dual-review && npm install`
Expected: bats installed under `node_modules/.bin/bats`. Verify: `node_modules/.bin/bats --version` prints `Bats 1.x.y`.

- [ ] **Step 5: Commit**

```bash
cd /home/noine/dual-review
git add LICENSE .gitignore package.json package-lock.json
git commit -m "chore: bootstrap repo (LICENSE, gitignore, bats devdep)"
```

---

### Task 2: Test helper (mocked codex CLI)

**Files:**
- Create: `/home/noine/dual-review/tests/test_helper.bash`

- [ ] **Step 1: Write test_helper.bash**

Write `/home/noine/dual-review/tests/test_helper.bash`:

```bash
#!/usr/bin/env bash
# Shared bats setup. Source via `load test_helper` (file extension omitted).

# REPO_ROOT: absolute path to repo root (one above tests/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# setup_test_env: create isolated tmp dir + mock codex on PATH.
# Sets TEST_TMP, CLAUDE_HOME, and prepends $TEST_TMP/bin to PATH.
setup_test_env() {
  TEST_TMP="$(mktemp -d -t dualrev-XXXXXX)"
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
# Output format:
#   ARGS: <arg1> <arg2> ...
#   STDIN:
#   <piped content>
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
```

- [ ] **Step 2: Quick sanity check (manual)**

Run: `cd /home/noine/dual-review && bash -c 'source tests/test_helper.bash; setup_test_env; install_codex_mock; echo "hi" | codex --foo bar; teardown_test_env'`
Expected: prints `ARGS: <--foo> <bar>` then `STDIN:` then `hi`.

- [ ] **Step 3: Commit**

```bash
git add tests/test_helper.bash
git commit -m "test: add bats test helper with codex mocks"
```

---

### Task 3: install.sh — write failing tests first

**Files:**
- Create: `/home/noine/dual-review/tests/install_test.bats`

- [ ] **Step 1: Write install_test.bats**

Write `/home/noine/dual-review/tests/install_test.bats`:

```bash
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
  # exactly one backup directory exists
  shopt -s nullglob
  backups=("$CLAUDE_HOME/skills/dual-review.bak."*)
  [ "${#backups[@]}" -eq 1 ]
  [ -f "${backups[0]}/old.txt" ]
}

@test "install fails clearly if skill source is missing" {
  rm -rf "$REPO_ROOT/skills/dual-review"
  run "$REPO_ROOT/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"skill source missing"* ]]
}
```

- [ ] **Step 2: Run tests, confirm they fail**

Run: `cd /home/noine/dual-review && node_modules/.bin/bats tests/install_test.bats`
Expected: 4 failures (install.sh doesn't exist yet).

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/install_test.bats
git commit -m "test: add failing tests for install.sh"
```

---

### Task 4: install.sh — minimal implementation

**Files:**
- Create: `/home/noine/dual-review/install.sh`

- [ ] **Step 1: Write install.sh**

Write `/home/noine/dual-review/install.sh`:

```bash
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
echo "✅ Installed: $SKILL_DST -> $SKILL_SRC"

if ! command -v codex >/dev/null 2>&1; then
  echo "⚠️  Warning: codex CLI not found in PATH. Install Codex CLI ≥ 0.57." >&2
fi
```

- [ ] **Step 2: chmod + run tests**

Run:
```bash
chmod +x /home/noine/dual-review/install.sh
cd /home/noine/dual-review && node_modules/.bin/bats tests/install_test.bats
```
Expected: 4 passes.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: implement install.sh (symlink + backup)"
```

---

### Task 5: uninstall.sh — write failing tests first

**Files:**
- Modify: `/home/noine/dual-review/tests/install_test.bats` (append)

- [ ] **Step 1: Append uninstall tests**

Append to `/home/noine/dual-review/tests/install_test.bats`:

```bash

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
```

- [ ] **Step 2: Run, confirm new tests fail**

Run: `cd /home/noine/dual-review && node_modules/.bin/bats tests/install_test.bats`
Expected: 4 passes (existing) + 3 failures (new uninstall tests).

- [ ] **Step 3: Commit**

```bash
git add tests/install_test.bats
git commit -m "test: add failing tests for uninstall.sh"
```

---

### Task 6: uninstall.sh — implementation

**Files:**
- Create: `/home/noine/dual-review/uninstall.sh`

- [ ] **Step 1: Write uninstall.sh**

Write `/home/noine/dual-review/uninstall.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SKILL_DST="${CLAUDE_HOME:-$HOME/.claude}/skills/dual-review"

if [[ -L "$SKILL_DST" ]]; then
  rm "$SKILL_DST"
  echo "✅ Removed symlink: $SKILL_DST"
elif [[ -e "$SKILL_DST" ]]; then
  echo "ERROR: $SKILL_DST is not a symlink. Skipping (manual removal required)." >&2
  exit 1
else
  echo "Nothing to remove at $SKILL_DST"
fi
```

- [ ] **Step 2: chmod + run tests**

Run:
```bash
chmod +x /home/noine/dual-review/uninstall.sh
cd /home/noine/dual-review && node_modules/.bin/bats tests/install_test.bats
```
Expected: 7 passes.

- [ ] **Step 3: Commit**

```bash
git add uninstall.sh
git commit -m "feat: implement uninstall.sh"
```

---

### Task 7: run-codex.sh — write failing tests first

**Files:**
- Create: `/home/noine/dual-review/tests/run-codex_test.bats`

- [ ] **Step 1: Write run-codex_test.bats**

Write `/home/noine/dual-review/tests/run-codex_test.bats`:

```bash
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
  run "$REPO_ROOT/$SCRIPT" review "$PROMPT"
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
```

- [ ] **Step 2: Run, confirm failures**

Run: `cd /home/noine/dual-review && node_modules/.bin/bats tests/run-codex_test.bats`
Expected: 12 failures (script not implemented).

- [ ] **Step 3: Commit**

```bash
git add tests/run-codex_test.bats
git commit -m "test: add failing tests for run-codex.sh"
```

---

### Task 8: run-codex.sh — implementation

**Files:**
- Create: `/home/noine/dual-review/skills/dual-review/scripts/run-codex.sh`

- [ ] **Step 1: Create scripts/ dir and write run-codex.sh**

Run: `mkdir -p /home/noine/dual-review/skills/dual-review/scripts`

Write `/home/noine/dual-review/skills/dual-review/scripts/run-codex.sh`:

```bash
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
#   0     success (codex success)
#   64    usage error (bad args / unknown mode)
#   66    prompt file not found
#   124   codex timed out
#   127   codex CLI not in PATH
#   *     any other codex non-zero exit propagates as-is

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
```

- [ ] **Step 2: chmod + run tests**

Run:
```bash
chmod +x /home/noine/dual-review/skills/dual-review/scripts/run-codex.sh
cd /home/noine/dual-review && node_modules/.bin/bats tests/run-codex_test.bats
```
Expected: 12 passes.

- [ ] **Step 3: Run all tests**

Run: `cd /home/noine/dual-review && node_modules/.bin/bats tests/`
Expected: 19 passes total (7 install + 12 run-codex).

- [ ] **Step 4: Commit**

```bash
git add skills/dual-review/scripts/run-codex.sh
git commit -m "feat: implement run-codex.sh (mode → model/reasoning presets)"
```

---

### Task 9: Codex prompt — review mode

**Files:**
- Create: `/home/noine/dual-review/skills/dual-review/prompts/review-codex.md`

- [ ] **Step 1: Create prompts/ dir and write review prompt**

Run: `mkdir -p /home/noine/dual-review/skills/dual-review/prompts`

Write `/home/noine/dual-review/skills/dual-review/prompts/review-codex.md`:

```markdown
あなたは熟練のシニアエンジニアです。以下のファイルを批判的にコードレビューしてください。

## レビュー対象
{{TARGET}}

## レビュー観点（必ず全て検討）
1. **セキュリティ**: 認証/認可の漏れ、入力検証、SQL/コマンドインジェクション、XSS、CSRF、秘密情報の漏洩、timing-safe な比較、暗号アルゴリズムの妥当性
2. **バグ**: ロジック誤り、境界条件 (off-by-one, null/undefined, 空コレクション)、競合状態、未処理の例外
3. **可読性**: 命名、関数の責務分離 (50 行超は要警戒)、ネスト深度 (4 段超は要警戒)、コメントの過不足
4. **設計**: 不要な抽象化 (YAGNI 違反)、責務の混在、密結合、依存方向
5. **テストカバレッジ**: テストが薄い・不在の領域、エッジケースの欠落
6. **型/契約**: 型の表現力不足、any の濫用、暗黙の null、契約 (precondition/postcondition) の不明瞭さ

## 追加コンテキスト
- 不明な依存関係や呼び出し元を確認したい場合、read-only で他ファイルを読んで構いません
- {{CONTEXT}}

## 出力フォーマット (これ以外のフォーマットで返さないでください)

各指摘を以下の形式で羅列してください:

```
[行番号] [カテゴリ] [深刻度: critical|high|medium|low] 説明

  改善案: <具体的な改善方法。コードスニペットがあれば歓迎>
```

最後に **"## サマリ"** セクションを設け、最重要指摘 3 件を優先順位順に列挙してください。

ファイルが完璧で何も指摘がない場合は **"指摘なし"** と一言だけ返してください。
```

- [ ] **Step 2: Verify file syntactically valid markdown**

Run: `head -3 /home/noine/dual-review/skills/dual-review/prompts/review-codex.md`
Expected: starts with `あなたは熟練の...`.

- [ ] **Step 3: Commit**

```bash
git add skills/dual-review/prompts/review-codex.md
git commit -m "feat: add Codex prompt template for review mode"
```

---

### Task 10: Codex prompt — plan critique

**Files:**
- Create: `/home/noine/dual-review/skills/dual-review/prompts/plan-critique.md`

- [ ] **Step 1: Write plan-critique.md**

Write `/home/noine/dual-review/skills/dual-review/prompts/plan-critique.md`:

```markdown
あなたは経験豊富なテックリードであり、レビュー対象の計画に対し**徹底的に批判的**な姿勢で臨んでください。
盲目的な同意は禁止です。問題が一つもないと判断する場合のみ「問題なし」と返してよい。

## 対象タスク
{{TARGET}}

## 批判すべき計画
以下が Claude が起案した計画です。

---
{{CLAUDE_DRAFT}}
---

## 批判観点（全て検討）
1. **実現可能性**: 必要な依存・権限・データ・人的リソースが揃っているか。前提が現実離れしていないか
2. **見落とし**: 言及されていない重要な要件、エッジケース、運用上の懸念 (監視/ログ/ロールバック/データ移行)
3. **代替案**: より単純・低コスト・高信頼の方法がないか。最低 1 つは別アプローチを提示
4. **順序の妥当性**: フェーズの順番は依存関係を満たすか。先にやるべきことを後回しにしていないか
5. **リスク評価の甘さ**: リスクが過小評価されていないか。発生確率・影響度・緩和策は妥当か
6. **YAGNI / 過剰設計**: 不要なフェーズ、過度な汎用化、現時点で必要ない機能が含まれていないか
7. **テスト戦略**: 計画にテスト方針が含まれているか。回帰の検出方法は明確か

## 追加コンテキスト
- read-only で関連コードを読んでよい
- {{CONTEXT}}

## 出力フォーマット (これ以外で返さない)

```
## 批判
1. [深刻度: critical|high|medium|low] [カテゴリ] 〈批判の要旨〉
   理由: ...
   提案する修正: ...

2. ...
```

その後:

```
## 代替アプローチ
〈計画と異なる別解を最低 1 つ。実装イメージとトレードオフを 3-5 行で〉
```

最後に:

```
## 総評
〈計画を採用すべきか、修正後採用すべきか、再検討すべきかの判断とその理由を 2-3 行で〉
```
```

- [ ] **Step 2: Commit**

```bash
git add skills/dual-review/prompts/plan-critique.md
git commit -m "feat: add Codex prompt template for plan critique"
```

---

### Task 11: Codex prompt — adversarial critique

**Files:**
- Create: `/home/noine/dual-review/skills/dual-review/prompts/critique.md`

- [ ] **Step 1: Write critique.md**

Write `/home/noine/dual-review/skills/dual-review/prompts/critique.md`:

```markdown
あなたは **devil's advocate**（悪魔の代弁者）です。Claude が作成した以下の成果物に対し、
可能な限り**反論・反例・別解**を提示し、Claude の主張を崩そうとしてください。

ただし、難癖や根拠のない否定は禁止です。具体的な技術的根拠を伴う批判のみを返してください。

## 批判対象（Claude の成果物 + Claude の意図/設計理由）

---
{{ARTIFACT}}
---

## 批判観点（全て検討）
1. **想定漏れ**: Claude が考慮しなかったケース・ユーザー・環境・障害シナリオ
2. **反例**: Claude の前提が成り立たない具体的状況。可能ならテストケースとして示す
3. **別解**: 同じ目的をより安全/単純/高速に達成する方法
4. **危険な前提**: 暗黙のうちに置かれている仮定で、本番で崩れうるもの
5. **副作用**: 変更が他のコンポーネント・性能・運用・既存テストに与える悪影響
6. **後方互換性**: 既存の利用者・データ・API への破壊的影響
7. **観測可能性の欠如**: ログ・メトリクス・トレースの不足、デバッグ困難な箇所

## 追加コンテキスト
- read-only で関連コードを読んでよい
- {{CONTEXT}}

## 出力フォーマット (これ以外で返さない)

```
## 批判
1. [深刻度: critical|high|medium|low] [カテゴリ] 〈批判の要旨〉
   反例 / 別解: ...
   根拠: ...

2. ...
```

その後:

```
## 最も致命的だと考える 1 点
〈最重要の指摘を 1 つだけ選び、なぜそれが致命的かを 3-5 行で〉
```

最後に:

```
## 総評
〈成果物をそのまま採用すべきか、修正後採用すべきか、却下すべきかの判断とその理由を 2-3 行で〉
```
```

- [ ] **Step 2: Commit**

```bash
git add skills/dual-review/prompts/critique.md
git commit -m "feat: add Codex prompt template for adversarial critique"
```

---

### Task 12: SKILL.md — main skill file

**Files:**
- Create: `/home/noine/dual-review/skills/dual-review/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Write `/home/noine/dual-review/skills/dual-review/SKILL.md`:

````markdown
---
name: dual-review
description: |
  Claude と Codex (ChatGPT Plus 契約の OpenAI Codex CLI) の二者でコードレビュー・実装計画立案・成果物批判を行うスキル。
  Claude が主体（議論をリード・統合・最終判断）、Codex は批評役（並列観点 / 反論 / 別解の提示）。コードは書かない (read-only)。

  3 モード:
  - review: 既存コードを Claude+Codex で並列レビューし観点を統合 (1 ラウンド)
  - plan: タスクの計画を Claude が起案 → Codex が批判 → Claude が改訂 (2 ラウンド)
  - critique: Claude の成果物 (PR/diff/直近の出力) を Codex に adversarial 批判させ、Claude が反論判断 (2 ラウンド)

  自然言語で以下が出たら自動起動:
  - 「Codex にも〜」「Codex にレビュー/批判/意見/反論させて」「Codex と一緒に」
  - 「もう一人の AI」「別モデルで」「二者で」「両方の視点」「対立する観点」
  - 「セカンドオピニオン」「devil's advocate」「赤チーム」
  - 「見落としないか」「本当にこれでいい？」「批判的に見て」(直近に Claude が成果物を出した文脈で)

  Claude が直前にコード/計画を出した直後の評価依頼、認証/課金/セキュリティ等の sensitive 領域、
  大きな PR を作る前 / マージ前にも提案する。
  スラッシュ: /dual <mode> <target>
---

# dual-review Skill

Claude (Anthropic) と Codex (OpenAI, ChatGPT Plus) の二者で**コードレビュー / 実装計画 / 成果物批判**を行います。Claude がオーケストレータ、Codex は批評役です。

## When to invoke

### 自動起動 (層1: 高確度)
ユーザーの発話に以下のいずれかが含まれたら**直ちに起動**:
- 「Codex にも〜」「Codex にレビュー/批判/意見/反論させて」「Codex と一緒に」
- 「もう一人の AI」「別モデルで」「二者で」「両方の視点」「対立する観点」
- 「赤チーム」「devil's advocate」「セカンドオピニオン」

### 自動起動 (層2: 文脈語 + 状況条件)
以下の語 + 直近文脈で自動モード判定:
- **Claude がコード/計画を直前に出した** + 「見落としないか」「本当にこれでいい？」「批判的に見て」「もっと良い方法ない？」「他の意見」 → `critique` モードで起動
- **既存コードへの言及（ファイルパス・関数名）** + 上記語 → `review` モードで起動
- **新規タスクの相談、計画なし** + 「どう実装」「設計」「計画」 → `plan` モードで起動

### 提案のみ (層3: 自動発火しない)
以下の場面では Claude が**起動を一行で提案**するだけにとどめ、ユーザー判断を仰ぐ:
- 大きな PR を作る前 / マージ前
- 認証・課金・セキュリティ等の sensitive 領域への変更
- アーキテクチャ的選択 (DB 選定、フレームワーク選定等)

提案文例: 「Codex にも批判してもらいますか？(`/dual critique`)」

### 誤発火対策（必ず守る）
- 同じ会話で**1 回起動したら、次の起動はユーザー明示要求まで控える**
- ユーザーが「Codex 不要」「Claude だけでいい」と言ったら**そのセッションでは起動停止**
- critique / plan モード起動時は**コスト警告**を 1 行: 「Codex を呼びます (`gpt-5.2 high`、目安 ~30 秒)」
- モード自動判定が曖昧な場合は `AskUserQuestion` で確認してから起動

## Modes

### review — 並列コードレビュー (1 ラウンド)

**入力**: ファイルパス（単数 or glob、例: `src/auth.ts`, `src/**/*.ts`）

**手順**:
1. Claude が対象を `Read` で読み込み、自身でレビュー（観点: セキュリティ / バグ / 可読性 / 設計 / テスト / 型）
2. **並列で** Codex を起動:
   - プロンプト: `<skill_dir>/prompts/review-codex.md` を Read し、`{{TARGET}}` をファイルパス、`{{CONTEXT}}` を周辺情報（言語/フレームワーク/呼び出し元）に置換
   - 一時ファイルに保存: `/tmp/dual-review-prompt-$(date +%s)-$RANDOM.md`
   - 実行: `<skill_dir>/scripts/run-codex.sh review <一時ファイル>`
3. Claude が両者の出力を **コンセンサス / Claude のみ / Codex のみ / 対立点** に分類して会話に表示
4. 推奨アクションを優先度付きで提示

**出力**: 会話のみ。以下のフォーマットで:

```markdown
## Code Review: <target>

### コンセンサス（両者一致）
- [行] [カテゴリ] [severity] 説明

### Claude のみが指摘
- ...

### Codex のみが指摘
- ...

### 対立点
- 〈論点〉: Claude=X / Codex=Y → Claude 判定: Z（理由）

### 推奨アクション (優先度順)
1. ...
```

### plan — 計画議論 (2 ラウンド)

**入力**: タスクの自然言語記述（例: `"JWT 認証への移行"`）

**手順**:
1. **R1 (Claude 起案)**: 目的 / 設計 / フェーズ / リスクを含む初版計画を作成
2. **R1.5 (一時ファイル)**: 起案を `/tmp/dual-plan-draft-$(date +%s)-$RANDOM.md` に保存
3. **R2 (Codex 批判)**:
   - プロンプト: `<skill_dir>/prompts/plan-critique.md` を Read し、`{{TARGET}}` をタスク記述、`{{CLAUDE_DRAFT}}` に R1.5 の内容を埋め込む
   - 一時ファイルに保存: `/tmp/dual-plan-prompt-...md`
   - 実行: `<skill_dir>/scripts/run-codex.sh plan-critique <一時ファイル>`
4. **R3 (Claude 改訂)**: Codex の各指摘を **採用 / 部分採用 / 却下（理由付き）** で判定し、最終計画を作成

**出力**: `<project_root>/docs/dual-review/YYYY-MM-DD-plan-<topic>.md`

```markdown
# Plan: <topic>

## 最終計画
（R3 改訂後の計画）

## 議論ログ
### R1: Claude 初版
…
### R2: Codex 批判 (gpt-5.2 high)
…
### R3: Claude 判定
- 指摘1: 採用 → 〈変更内容〉
- 指摘2: 却下 → 理由: …
```

### critique — 成果物 adversarial 批判 (2 ラウンド)

**入力（優先順）**:
1. `--pr <番号>`: GitHub PR の差分（`gh pr diff <番号>`）
2. `<path>`: 指定ファイル
3. 引数なし: 直近の `git diff HEAD`。空なら `git diff HEAD~1` にフォールバック。それも空なら `AskUserQuestion` で対象を尋ねる

**手順**:
1. **対象収集**: 上記入力に応じ Claude が `Read` / `gh pr diff` / `git diff` で取得
2. **R1 (一時ファイル)**: `/tmp/dual-critique-artifact-$(date +%s)-$RANDOM.md` に「成果物 + Claude の意図/設計理由」を書く
3. **R2 (Codex 批判)**:
   - プロンプト: `<skill_dir>/prompts/critique.md` を Read し、`{{ARTIFACT}}` に R1 の内容を埋め込む
   - 一時ファイルに保存
   - 実行: `<skill_dir>/scripts/run-codex.sh critique <一時ファイル>`
4. **R3 (Claude 反論判断)**: 各指摘を **正当(修正必要) / 部分的に正当 / 反論可能(理由付き)** で判定

**出力**: `<project_root>/docs/dual-review/YYYY-MM-DD-critique-<topic>.md`

```markdown
# Critique: <topic>

## 対象成果物
（diff 概要）

## 議論
### R1: Claude の意図
…
### R2: Codex の批判
…
### R3: Claude の判定
- 指摘1: 正当 → 修正タスク起票
- 指摘2: 反論 → 理由: …

## 結論
- 必要な修正: …
- 反論できた指摘: …
```

## Slash command

```
/dual review <path|glob>
/dual plan "<task description>"
/dual critique [<path>|--pr <number>]
```

オプション:
- `--reasoning <high|medium|low>`: reasoning effort 上書き（環境変数 `DUAL_REASONING`）
- `--model <gpt-5.2|gpt-5.2-mini>`: モデル上書き（環境変数 `DUAL_MODEL`）

## Codex execution policy

| モード/ラウンド | model | reasoning | sandbox |
|---|---|---|---|
| `review` (並列) | `gpt-5.2-mini` | `medium` | `read-only` |
| `plan` R2 (批判) | `gpt-5.2` | `high` | `read-only` |
| `critique` R2 (批判) | `gpt-5.2` | `high` | `read-only` |

**ChatGPT Plus 制約**: `gpt-5.2-max` および `xhigh` reasoning は Pro/Business 限定のため**未対応**。
**タイムアウト**: 300 秒。超過時は kill し Claude 単独結果で続行（警告表示）。

## Error handling

| 状況 | Claude の行動 |
|---|---|
| `codex` CLI 未検出 | 即停止し、`README.md` のインストール手順を表示 |
| Codex タイムアウト (>300s) | プロセス kill 済。Claude 単独結果のみで続行（警告表示） |
| レート制限ヒット | エラーを解釈し、`DUAL_MODEL=gpt-5.2-mini` でリトライを `AskUserQuestion` で提案 |
| 一時ファイル書込失敗 | `/tmp` 容量確認、停止 |
| 対象ファイル不在 | 即停止、`AskUserQuestion` で再指定 |
| `gh` CLI 未認証 (PR モード) | `gh auth status` 失敗。再ログイン手順を表示 |
| `git diff HEAD` 空 (critique) | `git diff HEAD~1` にフォールバック → さらに空なら `AskUserQuestion` |

## Anti-patterns (やってはいけないこと)

1. **同一会話で 2 回以上自動発火**しない（ユーザー明示要求があればその限りでない）
2. **ユーザーが断ったあと**もう一度勧めない
3. **コードを書かない**: このスキルは批評専用。`sandbox=read-only` を変えない
4. **Codex の出力を盲目的に採用しない**: Claude が必ず最終判断 (R3) を返す
5. **コスト警告を省略しない**: critique/plan 起動時は必ず 1 行通知
6. **`gpt-5.2-max` や `xhigh` を使わない**: ChatGPT Plus では使えない

## Implementation notes

- このスキル本体のパス: `~/.claude/skills/dual-review/`（symlink）
- スクリプト: `<skill_dir>/scripts/run-codex.sh`
- プロンプト: `<skill_dir>/prompts/{review-codex,plan-critique,critique}.md`
- プロンプトのプレースホルダ置換は Claude が `Read` → 文字列置換 → `Write` （`/tmp/` 配下）で行う
- 一時ファイルは `/tmp/dual-*-<unix_ts>-<random>.md` の命名規則で残置（手動削除はユーザー任意）
````

- [ ] **Step 2: Verify file**

Run: `head -5 /home/noine/dual-review/skills/dual-review/SKILL.md`
Expected: starts with `---` then `name: dual-review`.

- [ ] **Step 3: Run all tests (still passing)**

Run: `cd /home/noine/dual-review && node_modules/.bin/bats tests/`
Expected: 19 passes.

- [ ] **Step 4: Commit**

```bash
git add skills/dual-review/SKILL.md
git commit -m "feat: add SKILL.md (frontmatter, modes, triggers, anti-patterns)"
```

---

### Task 13: README.md

**Files:**
- Create: `/home/noine/dual-review/README.md`

- [ ] **Step 1: Write README.md**

Write `/home/noine/dual-review/README.md`:

````markdown
# dual-review

Claude Code skill for **dual-AI code review, planning, and adversarial critique** — pairs Claude (Anthropic) with Codex (OpenAI, ChatGPT Plus).

## What it does

Three modes:

| Mode | What it does | Rounds | Output |
|---|---|---|---|
| `review` | Claude + Codex review the same code in parallel; Claude integrates findings (consensus / unique / conflicts) | 1 | conversation |
| `plan` | Claude drafts a plan → Codex critiques it → Claude revises with verdicts | 2 | `docs/dual-review/*.md` |
| `critique` | Claude's artifact (PR/diff/output) gets adversarially critiqued by Codex; Claude rebuts/concedes | 2 | `docs/dual-review/*.md` |

Claude orchestrates and renders. Codex always runs **read-only** (`--sandbox read-only`). No code is written by this skill.

## Prerequisites

- [Claude Code](https://claude.com/claude-code) installed
- [Codex CLI](https://github.com/openai/codex) ≥ 0.57 with ChatGPT Plus account (`codex login`)
- `bash` 4+, GNU `coreutils` (`timeout`)
- `gh` CLI (only for `critique --pr`)

## Install

```bash
git clone https://github.com/noine32/dual-review.git ~/dual-review
cd ~/dual-review
./install.sh
```

This creates a symlink: `~/.claude/skills/dual-review` → `~/dual-review/skills/dual-review`. To update later, just `git pull` in the cloned dir.

### Custom Claude home

```bash
CLAUDE_HOME=/path/to/.claude ./install.sh
```

## Uninstall

```bash
~/dual-review/uninstall.sh
```

Only removes the symlink. Backups (`~/.claude/skills/dual-review.bak.*`) and the cloned repo are left alone.

## Usage

### Slash commands

```
/dual review src/auth.ts
/dual review "src/**/*.ts"
/dual plan "Migrate authentication to JWT"
/dual critique                    # uses git diff HEAD
/dual critique src/payment.ts
/dual critique --pr 123
```

### Natural-language triggers

The skill auto-fires on phrases like:

- 「Codex にもレビューさせて」
- 「もう一人の AI に批判させて」
- 「セカンドオピニオン欲しい」
- 「devil's advocate で見て」
- 「見落としないか確認」 (after Claude just produced a plan / code)

See `skills/dual-review/SKILL.md` for the full trigger list.

### Environment overrides

| Var | Default per mode | Effect |
|---|---|---|
| `DUAL_MODEL` | `gpt-5.2` or `gpt-5.2-mini` | Override Codex model |
| `DUAL_REASONING` | `high` or `medium` | Override reasoning effort |
| `DUAL_TIMEOUT` | `300` | Codex timeout in seconds |

ChatGPT Plus does **not** support `gpt-5.2-max` or `xhigh` reasoning — these defaults stay within Plus limits.

## Smoke test (manual)

After install, verify each mode in a Claude Code session:

1. **review**: open any source file, ask "src/foo.ts を Codex にもレビューしてもらえる？"
2. **plan**: ask "JWT 認証移行の計画を Codex とも練りたい"
3. **critique**: after Claude makes any code change, ask "今書いたやつ、Codex にも見せて批判してもらって"
4. **explicit**: type `/dual critique` after a `git diff` is non-empty

Each should produce two perspectives, and modes 2 and 3 should write a markdown log under `docs/dual-review/` of the **calling project**.

## Development

```bash
npm install              # install bats locally
npm test                 # run all bats tests
npm test tests/install_test.bats   # single file
```

## Repository layout

```
dual-review/
├── README.md
├── LICENSE
├── package.json
├── install.sh
├── uninstall.sh
├── skills/
│   └── dual-review/
│       ├── SKILL.md
│       ├── scripts/run-codex.sh
│       └── prompts/
│           ├── review-codex.md
│           ├── plan-critique.md
│           └── critique.md
├── tests/
│   ├── test_helper.bash
│   ├── install_test.bats
│   └── run-codex_test.bats
└── docs/
    ├── design.md
    └── plans/
```

## License

MIT — see [LICENSE](LICENSE).
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install/usage/triggers"
```

---

### Task 14: End-to-end install verification (no Codex call)

**Files:** none modified (verification only)

- [ ] **Step 1: Run full test suite from clean clone simulation**

Run:
```bash
cd /home/noine/dual-review
node_modules/.bin/bats tests/
```
Expected: 19 passes.

- [ ] **Step 2: Run install.sh against real ~/.claude (with backup)**

Run:
```bash
cd /home/noine/dual-review
./install.sh
ls -la ~/.claude/skills/dual-review
```
Expected:
- Output `✅ Installed: ...`
- `~/.claude/skills/dual-review` is a symlink pointing to `/home/noine/dual-review/skills/dual-review`
- Existing `~/.claude/skills/dual-review` (if any) was backed up to `dual-review.bak.<ts>`

- [ ] **Step 3: Verify skill discoverable by Claude Code**

Open a fresh Claude Code session in any directory and check that `dual-review` appears in the available-skills list (visible in `<system-reminder>` or via `/<tab>` completion).

If the skill is not discovered, check:
1. `ls -la ~/.claude/skills/dual-review/SKILL.md` (file readable through symlink)
2. The frontmatter `name: dual-review` is the first non-blank line after `---`

- [ ] **Step 4: No commit (verification step)**

---

### Task 15: Push to remote

- [ ] **Step 1: Inspect log**

Run: `cd /home/noine/dual-review && git log --oneline`
Expected: ~12 commits in this order:
1. docs: add initial design document
2. chore: bootstrap repo
3. test: add bats test helper
4. test: add failing tests for install.sh
5. feat: implement install.sh
6. test: add failing tests for uninstall.sh
7. feat: implement uninstall.sh
8. test: add failing tests for run-codex.sh
9. feat: implement run-codex.sh
10. feat: add Codex prompt template for review mode
11. feat: add Codex prompt template for plan critique
12. feat: add Codex prompt template for adversarial critique
13. feat: add SKILL.md
14. docs: add README

(Plus the plan doc commit if added.)

- [ ] **Step 2: Push**

Run: `cd /home/noine/dual-review && git push -u origin main`
Expected: pushes to https://github.com/noine32/dual-review

- [ ] **Step 3: Manual smoke test on the real Codex (optional, costs API)**

Open Claude Code in a different project, ask: "src/foo.ts を Codex にもレビューしてもらえる？" Verify that the skill auto-fires, both perspectives appear, and the integrated output looks reasonable. This step costs a small amount of ChatGPT Plus quota.

---

## Acceptance Criteria

- [ ] `git clone + ./install.sh` works on a clean machine
- [ ] `npm test` produces 19 passing bats tests
- [ ] `~/.claude/skills/dual-review/SKILL.md` is reachable via symlink
- [ ] Frontmatter `description` contains all natural-language triggers from spec §4.1
- [ ] `run-codex.sh review …` invokes `gpt-5.2-mini` with `medium` reasoning
- [ ] `run-codex.sh plan-critique …` and `run-codex.sh critique …` invoke `gpt-5.2` with `high`
- [ ] All env overrides (`DUAL_MODEL`, `DUAL_REASONING`, `DUAL_TIMEOUT`) work
- [ ] No reference to `gpt-5.2-max` or `xhigh` anywhere outside docs explaining why they are excluded
- [ ] Spec coverage: every numbered section in `docs/design.md` has at least one task implementing it
