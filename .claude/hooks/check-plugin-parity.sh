#!/usr/bin/env bash
# PostToolUse hook: when Claude edits a .sh or .ps1 under a parity-enforced
# plugin (currently coordinator/ and env-setup/), enforce that the sibling
# file (same basename, swapped extension) exists. Optionally run the
# PowerShell parity test for that plugin if `pwsh` is available.
#
# Emits a `decision: block` with feedback when out of parity so Claude fixes
# the companion file in the same turn.
set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{}'
  exit 0
fi

# Extract the file path from the tool input (Write / Edit / MultiEdit
# payloads all carry `tool_input.file_path`).
file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
if [[ -z "$file_path" ]]; then
  printf '%s\n' '{}'
  exit 0
fi

# Plugins enforced for .sh/.ps1 parity. Add a plugin to this list to opt
# it into the parity check.
ENFORCED_PLUGINS=(coordinator env-setup)

plugin_root=""
for p in "${ENFORCED_PLUGINS[@]}"; do
  marker="/${p}/"
  if [[ "$file_path" == *"$marker"* ]]; then
    plugin_root="${file_path%${marker}*}/${p}"
    break
  fi
done
[[ -z "$plugin_root" ]] && { printf '%s\n' '{}'; exit 0; }

# Only .sh or .ps1.
ext="${file_path##*.}"
if [[ "$ext" != "sh" && "$ext" != "ps1" ]]; then
  printf '%s\n' '{}'
  exit 0
fi

# Files that are inherently single-language (opt-out of bidirectional
# parity). test-parity.ps1 uses System.Management.Automation and cannot be
# meaningfully replicated in bash.
basename_only="${file_path##*/}"
case "$basename_only" in
  test-parity.sh|test-parity.ps1)
    printf '%s\n' '{}'
    exit 0
    ;;
esac

if [[ "$ext" == "sh" ]]; then
  sibling="${file_path%.sh}.ps1"
  sibling_kind="PowerShell"
else
  sibling="${file_path%.ps1}.sh"
  sibling_kind="bash"
fi

problems=()
if [[ ! -f "$sibling" ]]; then
  problems+=("Missing $sibling_kind companion: $sibling — parity requires a sibling script with the same behavior.")
fi

# Optional: run the plugin's pwsh parity test if available (catches
# missing files and PowerShell parse errors across the whole plugin).
if command -v pwsh >/dev/null 2>&1; then
  parity_test="$plugin_root/tests/test-parity.ps1"
  if [[ -f "$parity_test" ]]; then
    set +e
    pwsh_output=$(pwsh -NoProfile -File "$parity_test" 2>&1)
    pwsh_exit=$?
    set -e
    if (( pwsh_exit != 0 )); then
      problems+=("pwsh parity test failed ($parity_test):")
      problems+=("$pwsh_output")
    fi
  fi
fi

if (( ${#problems[@]} == 0 )); then
  printf '%s\n' '{}'
  exit 0
fi

plugin_name="$(basename "$plugin_root")"
msg="${plugin_name} plugin: shell-script parity violation detected after editing $file_path\n\n"
for p in "${problems[@]}"; do
  msg+="$p"$'\n'
done
msg+=$'\nRequired: keep bash (.sh) and PowerShell (.ps1) companions in sync so the plugin works on macOS, Linux, and Windows. After editing one, update the other to match in behavior.'

jq -n --arg reason "$msg" '{
  decision: "block",
  reason: $reason
}'
