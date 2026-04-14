#!/usr/bin/env bash
# Claude Code SubagentStop hook: remove agent_id/task_id from docs/plans/worktree-state.json
# running_tasks; set last_subagent_stop (requires jq).
set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

find_plans_root() {
  local d
  d=$(cd "${1:-.}" && pwd)
  while true; do
    if [[ -d "$d/docs/plans" ]]; then
      printf '%s' "$d"
      return 0
    fi
    [[ "$d" == "/" ]] && break
    d=$(dirname "$d")
  done
  pwd
}

if [[ -n "${CURSOR_WORKSPACE_ROOT:-}" ]]; then
  _start="$CURSOR_WORKSPACE_ROOT"
elif [[ -n "${CLAUDE_PROJECT_ROOT:-}" ]]; then
  _start="$CLAUDE_PROJECT_ROOT"
else
  _start="$PWD"
fi

ROOT=$(find_plans_root "$_start")
FILE="$ROOT/docs/plans/worktree-state.json"

[[ -d "$ROOT/docs/plans" ]] || exit 0

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Claude sends agent_id on SubagentStop; keep other keys for compatibility.
TASK_ID=$(echo "$INPUT" | jq -r '
  [
    .agent_id, .taskId, .task_id, .id, .subagentTaskId, .subagent_task_id,
    .task.taskId, .task.task_id, .task.id,
    .subagent.taskId, .subagent.task_id, .subagent.id
  ]
  | map(select(. != null))
  | map(tostring)
  | map(select(length > 0))
  | .[0] // empty
')

DEFAULT='{"last_subagent_stop":null,"running_tasks":[],"updated_at":null,"workspace":null}'

if [[ -f "$FILE" ]]; then
  if ! BASE=$(cat "$FILE") || ! echo "$BASE" | jq empty 2>/dev/null; then
    BASE="$DEFAULT"
  fi
else
  BASE="$DEFAULT"
fi

TMP="${FILE}.tmp.$$"
if echo "$BASE" | jq -S \
  --arg tid "$TASK_ID" \
  --arg now "$NOW" \
  --arg ws "$ROOT" \
  '
  if ($tid | length) > 0 then
    .running_tasks |= map(select(
      ((.task_id // .agent_id // "") | tostring) != $tid
    ))
  else
    .
  end
  | .last_subagent_stop = {
      status: "stopped",
      stopped_at: $now,
      task_id: (if ($tid | length) > 0 then $tid else null end)
    }
  | .updated_at = $now
  | .workspace = $ws
  ' >"$TMP"
then
  mv "$TMP" "$FILE"
else
  rm -f "$TMP"
  exit 0
fi

exit 0
