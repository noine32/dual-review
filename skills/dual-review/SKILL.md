---
name: dual-review
description: |
  Claude と Codex (ChatGPT Plus 契約の OpenAI Codex CLI) の二者でコードレビュー・実装計画立案・成果物批判を行うスキル。
  Claude が主体（議論をリード・統合・最終判断）、Codex は批評役（並列観点 / 反論 / 別解の提示）。**ソースコードは変更しない**（Codex は `--sandbox read-only` で起動）。議論ログ Markdown のみ `<project>/docs/dual-review/` と `/tmp/` に書き出す。

  3 モード:
  - review: 既存コードを Claude+Codex で並列レビューし観点を統合 (1 ラウンド)
  - plan: タスクの計画を Claude が起案 → Codex が批判 → Claude が改訂 (2 ラウンド)
  - critique: Claude の成果物 (PR/diff/直近の出力) を Codex に adversarial 批判させ、Claude が反論判断 (2 ラウンド)

  **自動起動するのは明示語のみ**（誤発火防止）:
  - 「Codex にも〜」「Codex にレビュー/批判/意見/反論させて」「Codex と一緒に」
  - 「もう一人の AI」「別モデルで」「二者で」「両方の視点」「対立する観点」
  - 「セカンドオピニオン」「devil's advocate」「赤チーム」

  曖昧語（「見落としないか」「本当にこれでいい？」「批判的に見て」等）や、
  認証/課金/セキュリティの sensitive 領域、大きな PR の前は**提案のみ**にとどめる
  （詳細は SKILL.md 本文の層3 参照）。
  スラッシュ: /dual <mode> <target>
---

# dual-review Skill

Claude (Anthropic) と Codex (OpenAI, ChatGPT Plus) の二者で**コードレビュー / 実装計画 / 成果物批判**を行います。Claude がオーケストレータ、Codex は批評役です。

**書き込みポリシー**:
- ソースコードは**書かない**（Codex は `--sandbox read-only`、Claude もこのスキル中はコード変更しない）
- 議論ログ Markdown は書き出す:
  - `/tmp/dual-*-<ts>.md`: Codex に渡すプロンプト本体（中間ファイル、削除自由）
  - `<project_root>/docs/dual-review/YYYY-MM-DD-<mode>-<topic>.md`: 最終ログ（plan / critique）

**`<project_root>` の解決ルール（順に試行）**:
1. `git rev-parse --show-toplevel` が成功すればその値
2. 失敗すれば現在の `pwd`
3. `<project_root>` がスキル本体の repo (`dual-review` 自身) と一致した場合、ユーザーに `AskUserQuestion` で書き込み先を確認（dogfood 時の事故防止）

## When to invoke

### 自動起動の条件 (層1)
**「明示語」 AND 「対象 or モードが特定可能」** の両方が満たされた場合のみ自動起動。

**明示語** (どれか含まれること):
- 「Codex にも〜」「Codex にレビュー/批判/意見/反論させて」「Codex と一緒に」
- 「もう一人の AI」「別モデルで」「二者で」「両方の視点」「対立する観点」
- 「赤チーム」「devil's advocate」「セカンドオピニオン」

**対象 or モードの特定** (以下のいずれか):
- ファイルパス / 関数名 / glob が言及されている → `review`
- 直近に Claude が**コードを書いた/編集した** → `critique`（成果物批判）
- 直近に Claude が**計画/設計を提示した** → `critique`（計画批判）
- 「PR #123」「`gh pr diff`」 → `critique --pr <番号>`
- スラッシュ `/dual <mode> ...` で明示

**明示語のみで対象/モードが不明な場合は `AskUserQuestion` で必ず確認**してから起動。

### 提案のみ (層2: 自動発火しない・Claude が一行で勧める)
以下の語/場面では Claude が**起動を提案する**にとどめ、ユーザー承認を待つ:
- 曖昧語のみ: 「見落としないか」「本当にこれでいい？」「批判的に見て」「もっと良い方法ない？」「他の意見」
  - 一般会話でも頻出するため誤発火回避
- 大きな PR を作る前 / マージ前
- 認証・課金・セキュリティ等の sensitive 領域への変更
- アーキテクチャ的選択 (DB 選定、フレームワーク選定等)

提案文例: 「Codex にも批判してもらいますか？(`/dual critique`)」

### 誤発火対策（毎回の起動前チェック）
起動前に以下を順にチェック:
1. **このセッションで既に dual-review を起動したか？** → Yes なら、ユーザーが今回明示要求していない限り提案のみに格下げ
2. **ユーザーが過去に「Codex 不要」「Claude だけでいい」と言ったか？** → Yes なら以後そのセッションでは起動しない
3. **モード自動判定が曖昧か？** → Yes なら `AskUserQuestion` で確認
4. **コスト警告**: critique / plan 起動時は実行前に 1 行通知: 「Codex を呼びます (`gpt-5.2 high`、目安 ~30 秒)」

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
- `--model <gpt-5.2>`: モデル上書き（環境変数 `DUAL_MODEL`）。ChatGPT Plus は `gpt-5.2` のみサポート

## Codex execution policy

| モード/ラウンド | model | reasoning | sandbox |
|---|---|---|---|
| `review` (並列) | `gpt-5.2` | `medium` | `read-only` |
| `plan` R2 (批判) | `gpt-5.2` | `high` | `read-only` |
| `critique` R2 (批判) | `gpt-5.2` | `high` | `read-only` |

**ChatGPT Plus 制約**: ChatGPT Plus アカウントでは `gpt-5.2` のみ利用可能。`gpt-5.2-mini` / `gpt-5.2-max` および `xhigh` reasoning は Pro/Business 限定のため**未対応**。コスト圧縮のため reasoning を変えてモード差を出す。
**タイムアウト**: 300 秒。超過時は kill し Claude 単独結果で続行（警告表示）。

## Error handling

| 状況 | Claude の行動 |
|---|---|
| `codex` CLI 未検出 | 即停止し、`README.md` のインストール手順を表示 |
| Codex タイムアウト (>300s) | プロセス kill 済。Claude 単独結果のみで続行（警告表示） |
| レート制限ヒット | エラーを解釈し、`DUAL_REASONING=low` でリトライを `AskUserQuestion` で提案 |
| 一時ファイル書込失敗 | `/tmp` 容量確認、停止 |
| 対象ファイル不在 | 即停止、`AskUserQuestion` で再指定 |
| `gh` CLI 未認証 (PR モード) | `gh auth status` 失敗。再ログイン手順を表示 |
| `git diff HEAD` 空 (critique) | `git diff HEAD~1` にフォールバック → さらに空なら `AskUserQuestion` |

## Anti-patterns (やってはいけないこと)

1. **同一会話で 2 回以上自動発火**しない（ユーザー明示要求があればその限りでない）
2. **ユーザーが断ったあと**もう一度勧めない
3. **ソースコードを書かない**: 批評専用。`sandbox=read-only` を変えない。議論ログ Markdown の書き出しは OK
4. **Codex の出力を盲目的に採用しない**: Claude が必ず最終判断 (R3) を返す
5. **コスト警告を省略しない**: critique/plan 起動時は必ず 1 行通知
6. **`gpt-5.2-mini` / `gpt-5.2-max` / `xhigh` を使わない**: ChatGPT Plus では `gpt-5.2` のみサポート

## Implementation notes

- このスキル本体のパス: `~/.claude/skills/dual-review/`（symlink）
- スクリプト: `<skill_dir>/scripts/run-codex.sh`
- プロンプト: `<skill_dir>/prompts/{review-codex,plan-critique,critique}.md`
- プロンプトのプレースホルダ置換は Claude が `Read` → 文字列置換 → `Write` （`/tmp/` 配下）で行う
- 一時ファイルは `/tmp/dual-*-<unix_ts>-<random>.md` の命名規則で残置（手動削除はユーザー任意）
