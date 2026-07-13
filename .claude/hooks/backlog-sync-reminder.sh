#!/usr/bin/env bash
# PostToolUse(Bash) hook — PR 作成/マージを検出したら backlog 同期のリマインダーを
# additionalContext として Claude に返す（CLAUDE.md の同期ルールの自動化）。
# 対象外のコマンドでは何も出力せず終了する。
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)

msg=""
case "$cmd" in
  *"gh pr merge"*)
    msg="[backlog-sync] PR がマージされました。CLAUDE.md の同期ルールに従い、いま同期してください: (1) 対応する backlog タスクを Done 化し finalSummary を記入 (2) 対応 GitHub Issue を gh issue close --comment でクローズ (3) 後続タスクが解放される場合は backlog で確認。"
    ;;
  *"gh pr create"*)
    msg="[backlog-sync] PR が作成されました。対応する backlog タスクに PR 番号とレビュー状況をコメント記録し、status が In Progress になっているか確認してください（マージ前に Done にしない）。"
    ;;
esac

[ -z "$msg" ] && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}' \
  "$(printf '%s' "$msg" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')"
