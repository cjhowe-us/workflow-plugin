#!/usr/bin/env bash
# SessionStart: hard-block if agent teams is not enabled (coordinator plugin
# cannot function without it). Warn about missing `gh` auth or missing
# `repos:` config, but do not block those.
set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

# Agent teams experimental flag — REQUIRED. Block session if missing.
if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]]; then
  echo "coordinator plugin: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is not set to 1." >&2
  echo "The orchestrator cannot dispatch workers without agent teams." >&2
  echo "" >&2
  echo "Invoke the env-setup plugin's skill to persist it for your shell:" >&2
  echo "    /env-setup:env-setup CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1" >&2
  echo "" >&2
  echo "Or run the scripts directly:" >&2
  echo "  bash/zsh/fish:  env-setup/skills/env-setup/scripts/ensure-env.sh --var CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS --value 1" >&2
  echo "  PowerShell:     pwsh -NoProfile -File env-setup/skills/env-setup/scripts/ensure-env.ps1 -VarName CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -VarValue 1" >&2
  echo "" >&2
  echo "Then restart your terminal." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{}'
  exit 0
fi

warnings=()

# gh CLI present and authenticated
if ! command -v gh >/dev/null 2>&1; then
  warnings+=("gh CLI is not installed — coordinator drives GitHub via gh.")
elif ! gh auth status >/dev/null 2>&1; then
  warnings+=("gh CLI is not authenticated — run 'gh auth login' with repo scope.")
fi

# Coordinator config file with repos list
cwd=$(echo "$INPUT" | jq -r '.cwd // empty')
[[ -z "$cwd" ]] && cwd="${PWD}"
cfg="$cwd/.claude/coordinator.local.md"
if [[ ! -f "$cfg" ]]; then
  warnings+=("No .claude/coordinator.local.md found at $cwd — orchestrator will prompt for the repos list on first /coordinator invocation.")
elif ! grep -qE '^repos:' "$cfg"; then
  warnings+=("$cfg has no 'repos:' list — orchestrator will prompt for it on first /coordinator invocation.")
fi

if (( ${#warnings[@]} == 0 )); then
  printf '%s\n' '{}'
  exit 0
fi

msg="coordinator plugin warnings:\n"
for w in "${warnings[@]}"; do
  msg+="  - ${w}\n"
done

jq -n --arg msg "$msg" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $msg
  }
}'
