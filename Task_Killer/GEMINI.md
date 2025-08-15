### 目的

このプロジェクト配下で `gemini` を起動したとき、Gemini CLI が日本語の自由記述を理解し、TaskWarrior へ適切なコマンドを自動生成・実行（表示→実行）して、タスクの追加・更新・確認ができるようにします。

### 前提

- TaskWarrior がインストール済み（例: `/usr/bin/task`）
- `~/.taskrc` に `uda.progress`（0-100 の数値 UDA）が定義済み
- `jq` がインストール済み（JSON パース用途）

### 全体方針（Gemini への指示）

Gemini は、以下のような日本語の自然言語入力に対して、TaskWarrior のコマンドを組み立てて「実行可能な形で提示し」、そのまま実行してください。実行前に必ず生成コマンドを表示し、`rc.confirmation:no` を付与して対話確認を省略します。必要に応じてプロジェクト（`project:<NAME>`）も付与してください。

- 例: 「タスクは形式言語とオートマトンで，締切は12-30-23:50，優先度は高め，プロジェクトはWebsite」
  - 生成方針: `task add` を使用し、締切は ISO 形式（`YYYY-MM-DDTHH:MM`、秒は任意）へ正規化、優先度は H/M/L に正規化。
  - 実行前に生成コマンドを表示し、続けて実行結果も表示。

### 正規化ルール

- **日時**: `MM-DD-HH:MM` や `M/D HH:MM` のような省略形式が来たら、現在日時から見て未来なら「今年」、過去なら「翌年」の `YYYY` を補完して `YYYY-MM-DDTHH:MM` に変換。
- **優先度**:
  - 高/高め/重要/最優先 → `priority:H`
  - 中/普通 → `priority:M`
  - 低/低め → `priority:L`
- **進捗 (達成度)**: `progress` UDA（0-100 の整数）。百分率表記（例: 50%）は数値に正規化。
- **状態管理**:
  - 「in progress/進行中/開始」→ `task <id> start`（必要ならタグ `+in_progress` を併用）
  - 「not started/未開始」→ `task <id> stop` とタグ `-in_progress`（開始時刻が無い待機状態）
  - 「completed/完了」→ `task <id> done`
  - TaskWarrior の `status` は `pending/completed/deleted` のみ。`status:in progress` などへは変更しないこと。

### タスク特定ポリシー

課題名（説明文）で特定します。曖昧一致で複数候補が出る場合は一覧を提示し、ユーザーに確認を求めます。スクリプト的には JSON エクスポートと `jq` を併用すると堅牢です。

```
# 候補検索（曖昧一致）: ID, Project, Description を表示（Project 未設定は -）
task rc.verbose:off export \
  | jq -r '.[] | select(.description | test("形式言語とオートマトン")) | "\(.id)\t\(.project // "-")\t\(.description)"'

# 単一特定（最初の1件の id を取得）
TARGET_ID="$(task rc.verbose:off export \
  | jq -r 'map(select(.description | test("形式言語とオートマトン")))[0].id')"
```

### コマンド・テンプレート

- 追加（締切・優先度あり、必要に応じてプロジェクト）
```
task rc.confirmation:no add "<タイトル>" [project:<プロジェクト名>] due:<YYYY-MM-DDTHH:MM> priority:<H|M|L>
```

- 進捗（達成度）の更新
```
task rc.confirmation:no <ID> modify progress:<0-100>
```

- 進行開始/停止/完了
```
task rc.confirmation:no <ID> start
task rc.confirmation:no <ID> stop
task rc.confirmation:no <ID> done
```

- 一覧/詳細
```
task next
task <ID> info
```

### 日本語入力からの例（Few-shot）

- 入力: 「タスクは形式言語とオートマトンで，締切は12-30-23:50，優先度は高め，プロジェクトはWebsite」
  - 生成/実行:
  ```bash
  # 今年または翌年の補完を行った上で（例: 2025 年想定）
  task rc.confirmation:no add "形式言語とオートマトン" project:Website due:2025-12-30T23:50 priority:H
  ```

- 入力: 「『形式言語とオートマトン』を進行中にして」
  - 生成/実行:
  ```bash
  TARGET_ID="$(task rc.verbose:off export | jq -r 'map(select(.description | test("形式言語とオートマトン")))[0].id')"
  task rc.confirmation:no ${TARGET_ID} start
  ```

- 入力: 「『形式言語とオートマトン』の達成度を50%に更新」
  - 生成/実行:
  ```bash
  TARGET_ID="$(task rc.verbose:off export | jq -r 'map(select(.description | test("形式言語とオートマトン")))[0].id')"
  task rc.confirmation:no ${TARGET_ID} modify progress:50
  ```

- 入力: 「『形式言語とオートマトン』のプロジェクトを Website に変更」
  - 生成/実行:
  ```bash
  TARGET_ID="$(task rc.verbose:off export | jq -r 'map(select(.description | test("形式言語とオートマトン")))[0].id')"
  task rc.confirmation:no ${TARGET_ID} modify project:Website
  ```

- 入力: 「今のタスクリストを表示」
  - 生成/実行:
  ```bash
  task next
  ```

- 入力: 「『形式言語とオートマトン』を完了に」
  - 生成/実行:
  ```bash
  TARGET_ID="$(task rc.verbose:off export | jq -r 'map(select(.description | test("形式言語とオートマトン")))[0].id')"
  task rc.confirmation:no ${TARGET_ID} done
  ```

### 出力ポリシー

- 実行前に必ず生成コマンドを表示してから実行する。
- 実行後は TaskWarrior の標準出力をそのまま表示し、要約も 1 行で付ける。
- 複数候補がある場合は ID / Project / Description の表を提示してユーザーに確認を求め、確定後に実行する（Project 未設定は `-`）。

### セーフティ

- 破壊的操作（`delete` など）は、明示的にユーザーが依頼した場合のみ実行。
- 予期せぬ多件数更新が発生しそうな場合は、実行前に必ず確認を入れる。

### 使い方（人間向け）

1. リポジトリのルートディレクトリで Gemini CLI を起動します。
```bash
cd /path/to/Task_Killer
gemini
```
2. 日本語で自由に指示してください。
   - 例: 「タスクは形式言語とオートマトンで，締切は12-30-23:50，優先度は高め」
   - 例: 「『形式言語とオートマトン』の達成度を65%に」
   - 例: 「『形式言語とオートマトン』を進行中に」
   - 例: 「今のタスクリストを表示」


