#!/usr/bin/env bash
# PostToolUse(Bash) hook — PR 作成/マージを検出したら backlog 同期のリマインダーを
# additionalContext として Claude に返す（CLAUDE.md の同期ルールの自動化）。
# 対象外のコマンドでは何も出力せず終了する。
#
# マッチはコマンド位置（行頭またはセパレータ ; && || | の直後）の
# `gh pr create|merge` のみ。コミットメッセージや echo 文字列の中に
# 同じ語が現れても発火しない（部分一致だと heredoc 内の文言で誤検知する）。
set -euo pipefail

input=$(cat)

kind=$(printf '%s' "$input" | python3 -c '
import sys, json, re
try:
    cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
except Exception:
    sys.exit(0)
# heredoc 本文とシングル/ダブルクォート文字列を除去してから判定する
cmd = re.sub(r"<<-?\s*.?(\w+).?\n.*?\n\1", "", cmd, flags=re.S)
cmd = re.sub(r"'\''[^'\'']*'\''", "", cmd)
cmd = re.sub(r"\"[^\"]*\"", "", cmd)
m = re.search(r"(?m)(?:^|[;&|(]\s*)gh\s+pr\s+(create|merge)\b", cmd)
print(m.group(1) if m else "")
' 2>/dev/null || true)

msg=""
case "$kind" in
  merge)
    msg="[backlog-sync] PR がマージされました。CLAUDE.md の同期ルールに従い、いま同期してください: (1) 対応する backlog タスクを Done 化し finalSummary を記入 (2) 対応 GitHub Issue を gh issue close --comment でクローズ (3) 後続タスクが解放される場合は backlog で確認。"
    ;;
  create)
    msg="[backlog-sync] PR が作成されました。対応する backlog タスクに PR 番号とレビュー状況をコメント記録し、status が In Progress になっているか確認してください（マージ前に Done にしない）。"
    ;;
esac

[ -z "$msg" ] && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}' \
  "$(printf '%s' "$msg" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')"
