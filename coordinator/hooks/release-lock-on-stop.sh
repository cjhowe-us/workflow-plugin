#!/usr/bin/env bash
# SubagentStop / TaskCompleted: release any PR locks held by the stopped
# coordinator-worker by scanning each configured repo and clearing markers
# whose lock_owner matches the stopped worker's id. Idempotent.
set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

if ! command -v jq >/dev/null 2>&1 || ! command -v gh >/dev/null 2>&1; then
  printf '%s\n' '{}'
  exit 0
fi

agent_id=$(echo "$INPUT" | jq -r '.agent_id // .subagent_id // .task_id // empty')
[[ -z "$agent_id" ]] && { printf '%s\n' '{}'; exit 0; }

# Skip if not a coordinator worker.
subagent_type=$(echo "$INPUT" | jq -r '.subagent_type // .agent_type // empty')
if [[ -n "$subagent_type" && "$subagent_type" != "coordinator-worker" ]]; then
  printf '%s\n' '{}'
  exit 0
fi

cwd=$(echo "$INPUT" | jq -r '.cwd // empty')
[[ -z "$cwd" ]] && cwd="${PWD}"
cfg="$cwd/.claude/coordinator.local.md"
[[ -f "$cfg" ]] || { printf '%s\n' '{}'; exit 0; }

# Parse repos list (`- owner/name` under `repos:`) from YAML frontmatter.
mapfile -t repos < <(awk '
  /^---/ { fm = !fm; next }
  !fm { next }
  /^repos:/ { in_repos = 1; next }
  in_repos && /^[^ ]/ { in_repos = 0 }
  in_repos && /^[[:space:]]*-[[:space:]]*/ {
    sub(/^[[:space:]]*-[[:space:]]*/, "")
    gsub(/"/, ""); gsub(/'\''/, "")
    print
  }
' "$cfg")
(( ${#repos[@]} )) || { printf '%s\n' '{}'; exit 0; }

plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Scan each repo and release any PRs whose marker owner matches this agent.
cleared=0
for repo in "${repos[@]}"; do
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    owner=$(echo "$rec" | jq -r '.lock_owner // ""')
    pr_num=$(echo "$rec" | jq -r '.number // empty')
    [[ -z "$pr_num" ]] && continue
    if [[ "$owner" == *"$agent_id"* ]]; then
      "$plugin_root/scripts/lock-release.sh" \
        --repo "$repo" --pr "$pr_num" --expected-owner "$owner" \
        >/dev/null 2>&1 || true
      cleared=$((cleared + 1))
    fi
  done < <("$plugin_root/scripts/pr-scan.sh" "$repo" 2>/dev/null || true)
done

printf '%s\n' '{}'
