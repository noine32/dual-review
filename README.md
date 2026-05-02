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

- [Claude Code](https://claude.com/claude-code) installed (any of: native macOS / Linux / WSL2 / Windows)
- [Codex CLI](https://github.com/openai/codex) >= 0.57 with ChatGPT Plus account (`codex login`)
- `bash` (any of):
  - macOS / Linux: built-in (3.2+)
  - WSL2: built-in
  - Windows native: install [Git for Windows](https://git-scm.com/download/win) (provides Git Bash)
- `timeout` (Linux GNU coreutils) **or** `gtimeout` (macOS via `brew install coreutils`) — optional but **recommended**:
  - Without it, set `DUAL_ALLOW_NO_TIMEOUT=1` to opt in to no-timeout execution (default refuses to run, to avoid hangs)
  - Windows native does not ship `timeout`; set the env var as shown in the Windows install section
- `gh` CLI (only for `critique --pr`)

## Install

### Linux / macOS / WSL2

```bash
git clone https://github.com/noine32/dual-review.git ~/dual-review
cd ~/dual-review
./install.sh
```

This creates a symlink: `~/.claude/skills/dual-review` -> `~/dual-review/skills/dual-review`. To update later, just `git pull` in the cloned dir.

Custom Claude home:
```bash
CLAUDE_HOME=/path/to/.claude ./install.sh
```

### Windows (native, with PowerShell)

If you run Claude Code natively on Windows (not via WSL), use the PowerShell installer:

```powershell
git clone https://github.com/noine32/dual-review.git $HOME\dual-review
cd $HOME\dual-review
.\install.ps1
```

This creates a symlink at `%USERPROFILE%\.claude\skills\dual-review` -> `%USERPROFILE%\dual-review\skills\dual-review`.

**Required**:
- **Developer Mode ON** (Settings → Update & Security → For developers → "Developer Mode") so non-admin users can create symlinks. Alternatively run PowerShell **as Administrator**.
- **Git for Windows** (provides `bash`, used by `scripts/run-codex.sh` at runtime). Download: <https://git-scm.com/download/win>
- **Codex CLI**: `npm install -g @openai/codex` then `codex login`

**Recommended Windows env**:
```powershell
# No 'timeout --foreground' on Windows; opt-in to no-timeout execution.
[System.Environment]::SetEnvironmentVariable('DUAL_ALLOW_NO_TIMEOUT', '1', 'User')
```
Restart the shell after setting this.

Custom Claude home:
```powershell
$env:CLAUDE_HOME = 'C:\custom\.claude'; .\install.ps1
```

### Using both WSL2 and Windows-native Claude Code

The two environments have separate `~/.claude` directories, so install in **both**:

| Environment | Cloned to | Install command |
|---|---|---|
| WSL2 | `~/dual-review` (Linux home) | `./install.sh` |
| Windows native | `%USERPROFILE%\dual-review` | `.\install.ps1` |

After both installs, the skill works in both Claude Code modes. Since the two clones are separate, `git pull` in each location to update independently.

## Uninstall

```bash
# Linux / macOS / WSL2
~/dual-review/uninstall.sh
```

```powershell
# Windows native
& "$HOME\dual-review\uninstall.ps1"
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

| Var | Default | Effect |
|---|---|---|
| `DUAL_MODEL` | `gpt-5.2` | Override Codex model (Plus only supports `gpt-5.2`) |
| `DUAL_REASONING` | `high` or `medium` | Override reasoning effort (`low|medium|high`) |
| `DUAL_TIMEOUT` | `300` | Codex timeout in seconds (1..3600) |
| `CODEX_CD` | `$PWD` | Directory codex runs in (sandbox read-only resolves paths from here) |
| `DUAL_REQUIRE_GIT_REPO` | `0` | `1` to drop `--skip-git-repo-check` |
| `DUAL_ALLOW_NO_TIMEOUT` | `0` | `1` to allow running without `timeout`/`gtimeout` (may hang) |
| `DUAL_SHOW_STDERR` | `0` | `1` to print codex stderr inline on failure (may leak secrets) |

### Scaling guidance (from real-world dogfood)

- **5–7 files per call** is the sweet spot for `review` mode at default `gpt-5.2` + `medium` reasoning.
- Large codebases: split into multiple `/dual review ...` calls instead of one giant target.
- If you must batch many files: `DUAL_TIMEOUT=600` and `DUAL_REASONING=low`.

### Reviewing a project in a different directory

If your CWD is not the project being reviewed, set `CODEX_CD`:

```bash
CODEX_CD=/path/to/target-project /dual review src/auth.ts
```

Without this, Codex's `--sandbox read-only` blocks reads outside the inherited CWD and returns 0 findings.

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
