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
- [Codex CLI](https://github.com/openai/codex) >= 0.57 with ChatGPT Plus account (`codex login`)
- `bash` 3.2+ (macOS default works; uses `${RANDOM}` and `[[ ]]` only)
- `timeout` (Linux GNU coreutils) **or** `gtimeout` (macOS via `brew install coreutils`) — **optional**: if neither is available, the script warns and runs without a timeout
- `gh` CLI (only for `critique --pr`)

## Install

```bash
git clone https://github.com/noine32/dual-review.git ~/dual-review
cd ~/dual-review
./install.sh
```

This creates a symlink: `~/.claude/skills/dual-review` -> `~/dual-review/skills/dual-review`. To update later, just `git pull` in the cloned dir.

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

**Auto-fire** (explicit phrases only):

- 「Codex にもレビューさせて」 / 「Codex に批判させて」
- 「もう一人の AI に〜」 / 「別モデルで〜」
- 「セカンドオピニオン欲しい」 / 「devil's advocate で見て」 / 「赤チーム」

**Suggest only** (Claude offers `/dual` but waits for user confirmation):

- Ambiguous phrases that overlap with everyday conversation: 「見落としないか」「本当にこれでいい？」「批判的に見て」「もっと良い方法ない？」
- Sensitive areas: auth / payments / security
- Pre-merge / large PR review / architectural choices

See `skills/dual-review/SKILL.md` for the full trigger list and anti-misfire rules.

### Environment overrides

| Var | Default per mode | Effect |
|---|---|---|
| `DUAL_MODEL` | `gpt-5.2` (all modes) | Override Codex model |
| `DUAL_REASONING` | `high` or `medium` | Override reasoning effort |
| `DUAL_TIMEOUT` | `300` | Codex timeout in seconds |

**ChatGPT Plus only supports `gpt-5.2`.** Modes differ by `reasoning_effort` (review=`medium`, plan/critique=`high`) instead of model. `gpt-5.2-mini` / `gpt-5.2-max` and `xhigh` reasoning are Pro/Business-only and rejected by the API for Plus accounts.

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
node_modules/.bin/bats tests/install_test.bats   # single file
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

MIT - see [LICENSE](LICENSE).
