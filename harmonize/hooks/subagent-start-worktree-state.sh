#!/usr/bin/env bash
# Claude Code SubagentStart: append to running_tasks in the primary repo only.
# Git: one shared object DB; primary working tree + linked worktrees form a layout hierarchy.
# tree_path mirrors subagent parent/child when parent_agent_id is present in the hook JSON.
set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Repository root (dirname of common .git) — same for primary and every linked worktree.
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

# linked = git dir lives under .git/worktrees/...; root = primary working tree for this clone.
worktree_hierarchy_tier() {
  local d="$1"
  local gd
  gd=$(git -C "$d" rev-parse --git-dir 2>/dev/null) || {
    printf '%s' "unknown"
    return 0
  }
  if [[ "$gd" == *"/worktrees/"* ]] || [[ "$gd" == *"/.git/worktrees/"* ]]; then
    printf '%s' "linked"
  else
    printf '%s' "root"
  fi
}

_hook_cwd=$(echo "$INPUT" | jq -r '.cwd // empty')
if [[ -z "$_hook_cwd" ]]; then
  _hook_cwd="${CURSOR_WORKSPACE_ROOT:-${CLAUDE_PROJECT_ROOT:-$PWD}}"
fi

CWD_REAL=$(cd "$_hook_cwd" && pwd) || exit 0

ROOT=$(main_repo_root "$CWD_REAL") || exit 0
FILE="$ROOT/docs/plans/worktree-state.json"
mkdir -p "$ROOT/docs/plans"

WT_TIER=$(worktree_hierarchy_tier "$CWD_REAL")

AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
[[ -n "$AGENT_ID" ]] || exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"')
PARENT_ID=$(echo "$INPUT" | jq -r '
  .parent_agent_id // .source_agent_id // .caller_agent_id // .parent.agent_id // empty
')
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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
  --arg aid "$AGENT_ID" \
  --arg atype "$AGENT_TYPE" \
  --arg cwd "$CWD_REAL" \
  --arg now "$NOW" \
  --arg pid "$PARENT_ID" \
  --arg tier "$WT_TIER" \
  --arg ws "$ROOT" \
  '
  def compute_tree_path($tasks; $pid; $aid; $atype):
    if ($pid | length) == 0 then "\($atype)/\($aid)"
    else
      ([$tasks[]? | select(.agent_id == $pid) | .tree_path] | first // "") as $pp
      | if ($pp | length) > 0 then "\($pp)/\($atype)/\($aid)"
        else "\($atype)/\($aid)"
        end
    end;
  . as $orig
  | .running_tasks |= (
      map(select(((.agent_id // .task_id // "") | tostring) != $aid))
      + [{
          agent_id: $aid,
          branch: null,
          parent_agent_id: (if ($pid | length) > 0 then $pid else null end),
          plan_id: null,
          started_at: $now,
          status: "running",
          subagent_type: $atype,
          task_id: $aid,
          tree_path: compute_tree_path($orig.running_tasks; $pid; $aid; $atype),
          worktree_hierarchy: $tier,
          worktree_path: $cwd
        }]
    )
  | .last_subagent_start = {
      agent_id: $aid,
      agent_type: $atype,
      parent_agent_id: (if ($pid | length) > 0 then $pid else null end),
      started_at: $now,
      tree_path: compute_tree_path($orig.running_tasks; $pid; $aid; $atype),
      worktree_hierarchy: $tier,
      worktree_path: $cwd
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
