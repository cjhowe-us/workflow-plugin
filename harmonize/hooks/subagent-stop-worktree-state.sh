#!/usr/bin/env bash
# Claude Code SubagentStop: prune running_tasks in the *primary* repo only.
set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

main_repo_root() {
  local d="$1"
  [[ -n "$d" ]] || return 1
  d=$(cd "$d" && pwd) || return 1
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || return 1
  local g
  g=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || g=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null) || return 1
  if [[ "$g" != /* ]]; then
    local top
    top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || return 1
    g="$top/$g"
  fi
  dirname "$g"
}

_hook_cwd=$(echo "$INPUT" | jq -r '.cwd // empty')
if [[ -z "$_hook_cwd" ]]; then
  _hook_cwd="${CURSOR_WORKSPACE_ROOT:-${CLAUDE_PROJECT_ROOT:-$PWD}}"
fi

ROOT=$(main_repo_root "$_hook_cwd") || exit 0
FILE="$ROOT/docs/plans/worktree-state.json"
mkdir -p "$ROOT/docs/plans"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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

DEFAULT='{"last_subagent_start":null,"last_subagent_stop":null,"running_tasks":[],"updated_at":null,"workspace":null}'

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
      agent_id: (if ($tid | length) > 0 then $tid else null end),
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
