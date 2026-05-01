# dual-review Skill — Design Document

- **Date**: 2026-05-02
- **Repository**: https://github.com/noine32/dual-review
- **Author**: noine32 (with Claude Opus 4.7)
- **Status**: Draft (pending user review)

## 1. Purpose

Claude Code から ChatGPT Plus 契約の Codex CLI を呼び出し、**Claude と Codex の二者の視点**でコードレビュー・実装計画立案・成果物批判を行うスキル。Claude が主体（議論をリード・統合・最終判断）、Codex は批評役（並列観点 / 反論 / 別解の提示）。

既存スキルとの差別化:
- `codex` (既存): Codex CLI を呼ぶための薄いラッパ。本スキルが内部で利用。
- `claude-codex-workflow` (既存): Claude 計画 → Codex 実装 の片道パイプライン。実装が目的。
- `parallel-dev` (既存): 並列開発ワークフロー。
- `dual-review` (本スキル): **批評と評価のみ**。コードは書かない。Codex は read-only で動く。

## 2. Non-Goals

- コードを書く / 修正する（Codex sandbox は read-only 固定）
- 自動マージや自動コミット
- 3 者以上の AI を使う（将来拡張可能だが本スコープ外）
- 実装比較（同じ task を両者に実装させる）モード — 別スキルで扱う

## 3. Modes

| モード | 役割 | ラウンド構成 | 出力先 |
|---|---|---|---|
| `review` | 既存コードを Claude+Codex で並列レビューし観点を統合 | 1 (並列) | 会話のみ |
| `plan` | タスクの計画を Claude が起案 → Codex が批判 → Claude が改訂 | 2 | ファイル |
| `critique` | Claude の成果物（PR/diff/直近の出力）を Codex に批判させ、Claude が反論判断 | 2 | ファイル |

### 3.1 `review` モード

**入力**: ファイルパス（単数 or glob）

**フロー**:
1. Claude が対象を `Read` で読み込み、自身でレビュー（セキュリティ / 可読性 / バグ / テスト不足 / 設計）
2. **並列で** Codex を `gpt-5.2-mini reasoning=medium` で起動し、同じ対象をレビューさせる
3. Claude が両出力を **コンセンサス / Claude のみ / Codex のみ / 対立点** に分類して統合表示
4. 推奨アクションを優先度付きで提示

**Codex プロンプト要旨** (`prompts/review-codex.md`):
- 対象: `{{TARGET}}` のファイル群
- 観点: セキュリティ・パフォーマンス・可読性・バグ・テストカバレッジ・型/契約
- 出力フォーマット: `[行番号] [カテゴリ] [深刻度: critical/high/medium/low] 説明 + 改善案`
- 不明な依存先は読みに行ってよい（read-only sandbox 内）

**出力（会話のみ）**:
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

### 3.2 `plan` モード

**入力**: タスクの自然言語記述（例: "JWT 認証への移行"）

**フロー**:
1. **R1 (Claude 起案)**: 目的 / 設計 / フェーズ / リスクを含む初版計画を作成
2. **R1.5 (一時ファイル化)**: `/tmp/dual-plan-<unix_ts>-<rand6>.md` に Claude の計画を保存
3. **R2 (Codex 批判)**: `gpt-5.2 reasoning=high` で Codex 起動。観点: 実現可能性 / 見落とし / 代替案 / 順序の妥当性 / リスク評価の甘さ
4. **R3 (Claude 改訂)**: Codex の各指摘を **採用 / 部分採用 / 却下（理由付き）** で判定し、最終計画を作成

**Codex プロンプト要旨** (`prompts/plan-critique.md`):
- 「次の計画案を批判的にレビュー: `{{CLAUDE_DRAFT}}`」
- スタンス: 想定外パターンを探せ / 代替案を最低 1 つ提示 / リスクを過小評価していないか
- 出力フォーマット: 番号付き批判リスト（深刻度付き）+ 提案する代替アプローチ

**出力**: `<project>/docs/dual-review/YYYY-MM-DD-plan-<topic>.md`
```markdown
# Plan: <topic>

## 最終計画
（R3 改訂後の計画）

## 議論ログ
### R1: Claude 初版
### R2: Codex 批判 (gpt-5.2 high)
### R3: Claude 判定
- 指摘N: 採用/部分採用/却下 + 理由
```

### 3.3 `critique` モード

**入力（優先順）**:
1. `--pr <番号>`: GitHub PR の差分（`gh pr diff <番号>`）
2. `<path>`: 指定ファイル
3. 引数なし: 直近の `git diff HEAD`（直前のコミットからの未コミット変更）。空の場合は `git diff HEAD~1` にフォールバック。それも空なら `AskUserQuestion` で対象を尋ねる。

**フロー**:
1. **対象収集**: 上記入力に応じ Claude が `Read` / `gh` / `git diff` で取得
2. **R1 (一時ファイル化)**: `/tmp/dual-critique-<unix_ts>-<rand6>.md` に「対象成果物 + Claude の意図/設計理由」を書く（Codex に対立視点を促すコンテキスト）
3. **R2 (Codex 批判)**: `gpt-5.2 reasoning=high` で adversarial 批判
   - スタンス: 「Claude の主張をなるべく崩す」想定漏れ / 反例 / 別解 / 危険な前提の指摘
4. **R3 (Claude 反論判断)**: 各指摘を **正当(修正必要) / 部分的に正当 / 反論可能(理由付き)** で判定

**Codex プロンプト要旨** (`prompts/critique.md`):
- 「以下の成果物に対し devil's advocate として批判」
- 出力フォーマット: 番号付き批判（深刻度・カテゴリ・反例 or 別解）

**出力**: `<project>/docs/dual-review/YYYY-MM-DD-critique-<topic>.md`

## 4. Invocation

### 4.1 自然言語トリガ（メイン経路）

`SKILL.md` の `description` に以下のトリガを記述し、Claude が会話文脈から自動判定して起動:

**層1（高確度）**: 「Codex にも〜」「Codex にレビュー/批判/意見/反論」「Codex と一緒に」「もう一人の AI」「別モデルで」「二者で」「両方の視点」「対立する観点」「赤チーム」「devil's advocate」

**層2（文脈語 + 状況条件）**: 「見落としないか」「本当にこれでいい？」「もっと良い方法」「批判的に見て」「セカンドオピニオン」 + 直近文脈で自動モード判定:
- Claude が**コードを書いた直後** → `critique`
- Claude が**計画/設計を提示した直後** → `critique`
- Claude が**既存コードのレビューを返した直後** → `review`
- **新規タスクの相談、計画なし** → `plan`

**層3（提案のみ・自動発火しない）**: 大きな PR 前 / マージ前 / セキュリティ・認証・課金等の sensitive 領域 / アーキテクチャ選定 → Claude が `/dual` 実行を一行で提案

### 4.2 スラッシュコマンド（明示経路）

```
/dual review <path|glob>
/dual plan "<task description>"
/dual critique [<path>|--pr <number>]
```

オプション:
- `--reasoning <xhigh|high|medium|low>`: モデル reasoning 上書き
- `--model <gpt-5.2|gpt-5.2-mini>`: モデル上書き

### 4.3 誤発火対策

- **同一会話で 1 回起動したら**、次の起動はユーザー明示要求まで待つ（Claude が会話文脈で記憶。永続化はしない）
- ユーザーが「Codex 不要」「Claude だけでいい」と言ったら**そのセッションで停止**（同上、会話文脈ベース）
- **コスト警告**: critique/plan 起動時に「Codex を呼びます (`gpt-5.2 high`、目安〜30秒)」と一行事前通知
- モード自動判定が曖昧な場合は `AskUserQuestion` で確認

## 5. Codex Execution Policy

| モード/ラウンド | model | reasoning | sandbox |
|---|---|---|---|
| `review` (並列) | `gpt-5.2-mini` | `medium` | `read-only` |
| `plan` R2 (批判) | `gpt-5.2` | `high` | `read-only` |
| `critique` R2 (批判) | `gpt-5.2` | `high` | `read-only` |

**ChatGPT Plus 制約**: `gpt-5.2-max` および `xhigh` reasoning は Pro/Business 限定のため未対応。
**共通フラグ**: `--skip-git-repo-check`, stderr suppression (`2>/dev/null`)
**タイムアウト**: 300 秒。超過時は kill、Claude 単独結果で続行（警告付き）。

## 6. Repository Layout

```
dual-review/
├── README.md                       # インストール・使い方・トリガ例
├── LICENSE                         # MIT
├── install.sh                      # ~/.claude/skills/dual-review に symlink
├── uninstall.sh                    # symlink 削除
├── skills/
│   └── dual-review/
│       ├── SKILL.md                # frontmatter付き、自然言語トリガ網羅
│       ├── prompts/
│       │   ├── review-codex.md
│       │   ├── plan-critique.md
│       │   └── critique.md
│       └── scripts/
│           └── run-codex.sh        # Codex 起動ヘルパー
├── tests/
│   ├── install_test.bats
│   └── run-codex_test.bats
└── docs/
    └── design.md                   # 本ドキュメント
```

## 7. Component Specs

### 7.1 `install.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/dual-review"
SKILL_DST="${CLAUDE_HOME:-$HOME/.claude}/skills/dual-review"

[[ -d "$SKILL_SRC" ]] || { echo "ERROR: skill source missing: $SKILL_SRC" >&2; exit 1; }
mkdir -p "$(dirname "$SKILL_DST")"

if [[ -L "$SKILL_DST" ]]; then
  echo "Removing old symlink: $SKILL_DST"
  rm "$SKILL_DST"
elif [[ -e "$SKILL_DST" ]]; then
  BACKUP="${SKILL_DST}.bak.$(date +%s)"
  echo "Backing up existing dir: $BACKUP"
  mv "$SKILL_DST" "$BACKUP"
fi

ln -s "$SKILL_SRC" "$SKILL_DST"
echo "✅ Installed: $SKILL_DST -> $SKILL_SRC"
command -v codex >/dev/null 2>&1 || echo "⚠️  Warning: codex CLI not found in PATH"
```

冪等性: 同じ symlink を再作成しても安全。

### 7.2 `run-codex.sh`

```bash
#!/usr/bin/env bash
# Usage: run-codex.sh <codex-mode> <prompt-file>
# codex-mode (Codex 起動時のプリセット名):
#   review          → gpt-5.2-mini, reasoning=medium  (review モードの並列レビュー側)
#   plan-critique   → gpt-5.2,      reasoning=high    (plan モードの R2 批判)
#   critique        → gpt-5.2,      reasoning=high    (critique モードの R2 批判)
# Env overrides: DUAL_MODEL, DUAL_REASONING, DUAL_TIMEOUT (default 300)
```

**注**: `codex-mode` はスキルの 3 モード（review/plan/critique）と完全には 1:1 ではない。`plan` モードは Claude 起案 → Codex 批判の構造のため、Codex 起動時のプリセット名は `plan-critique` となる。Claude 側のオーケストレーションが正しいプリセットを選ぶ。

責務:
- mode → (model, reasoning) マッピング
- env override 反映
- `codex exec --skip-git-repo-check --sandbox read-only -m <model> --config model_reasoning_effort=<level> 2>/dev/null < <prompt-file>`
- timeout 適用、非ゼロ終了時は exit code と stderr 末尾を渡す

### 7.3 プロンプトテンプレート

3 ファイル (`review-codex.md`, `plan-critique.md`, `critique.md`)。プレースホルダ:
- `{{TARGET}}`: 対象ファイルパス（review）
- `{{CLAUDE_DRAFT}}`: Claude の起案内容（plan）
- `{{ARTIFACT}}`: Claude の成果物 + 意図（critique）
- `{{CONTEXT}}`: 周辺コンテキスト（任意）

Claude は `Read` でテンプレートを読み、置換後 `/tmp/dual-prompt-<id>.md` に書き、`run-codex.sh` の引数として渡す。

### 7.4 `SKILL.md` 構造

```yaml
---
name: dual-review
description: |
  Claude と Codex (ChatGPT Plus) の二者でコードレビュー / 計画立案 / 成果物批判を行う。
  3 モード: review (並列レビュー) / plan (議論しながら計画策定) / critique (Claude 成果物の adversarial 批判)。

  自然言語の以下のトリガで自動起動:
  - 「Codex にも〜」「Codex にレビュー/批判/意見させて」「Codex と一緒に」「もう一人の AI」「別モデルで」
  - 「セカンドオピニオン」「見落としないか」「本当にこれでいい？」「批判的に見て」「対立する観点で」「devil's advocate」「赤チーム」

  Claude が直前に書いたコード/計画への評価依頼や、レビュー対象の sensitive 領域（認証・課金・セキュリティ）でも提案する。
  スラッシュ: /dual <mode> <target>
---
```

本文: 起動方法、モード詳細、自動モード判定ロジック、誤発火対策、トラブルシュート。

## 8. Error Handling

| 状況 | 処理 |
|---|---|
| `codex` CLI 未検出 | 即停止、`README.md` のインストール手順を表示 |
| Codex タイムアウト (>300秒) | プロセス kill、Claude 単独結果で続行（警告） |
| レート制限ヒット | エラー解釈、`gpt-5.2-mini` フォールバックを `AskUserQuestion` で提案 |
| 一時ファイル書込失敗 | `/tmp` 容量チェック、停止 |
| 対象ファイル不在 | 即停止、`AskUserQuestion` で再指定 |
| プロンプトテンプレート破損 | `./install.sh` 再実行を促す |
| `gh` CLI 未認証 (PR モード) | `gh auth status` 失敗、再ログイン手順を提示 |

## 9. Testing

### 9.1 ユニットテスト (bats)

- `tests/install_test.bats`:
  - 新規インストール: symlink が作成されること
  - 既存 symlink 上書き: 冪等
  - 既存ディレクトリのバックアップ
  - skill source 不在時に exit 1
- `tests/run-codex_test.bats`:
  - mode → model/reasoning マッピング検証（モック `codex` で stdout キャプチャ）
  - env override (`DUAL_MODEL`, `DUAL_REASONING`) の反映
  - timeout 強制 kill

### 9.2 手動シナリオ（README に記載）

1. **review**: 既存ファイル `src/foo.ts` に対し `/dual review src/foo.ts` を実行、両者の指摘が表示されること
2. **plan**: `/dual plan "認証を JWT 化"` で議論ログ + 最終計画が `docs/dual-review/` に出力されること
3. **critique**: 直近の `git diff` に対し `/dual critique` で批判ログが出ること
4. **自然言語トリガ**: 「これ Codex にも見せて」と言って自動発火すること

### 9.3 CI（後続イテレーション）

GitHub Actions で `bats tests/` を main push 時に実行。Codex CLI が必要なテストは skip タグで分離。

## 10. Out of Scope (Future)

- 3 者以上の AI 比較
- 実装比較モード（両者に同タスクを実装させる）
- 過去議論ログの index 化と検索
- ローカルキャッシュによる Codex コスト削減

## 11. Open Questions

なし（ブレインストーミング段階で全て解決済み）。

## 12. Acceptance Criteria

- [ ] `git clone + ./install.sh` で別環境にインストールできる
- [ ] `/dual review <file>` が両者のレビューを統合表示する
- [ ] `/dual plan "<task>"` が `docs/dual-review/` にログを出力する
- [ ] `/dual critique` が直近 diff を対象に批判ログを出力する
- [ ] 自然言語「Codex にも見せて」で自動発火する
- [ ] ChatGPT Plus 制約内で動く（`gpt-5.2-max` / `xhigh` を使わない）
- [ ] `bats tests/` が green
- [ ] README に上記 4 シナリオが記載されている
