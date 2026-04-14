#!/bin/bash
# PostToolUse hook: format/check JSON, TOML, YAML files
FILE=$(cat | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

EXT="${FILE##*.}"

case "$EXT" in
  toml)
    command -v taplo >/dev/null 2>&1 || exit 0
    taplo fmt "$FILE" 2>/dev/null
    ;;
  json)
    command -v jq >/dev/null 2>&1 || exit 0
    TMP=$(mktemp)
    if jq --sort-keys . "$FILE" > "$TMP" 2>/dev/null; then
      mv "$TMP" "$FILE"
    else
      rm -f "$TMP"
    fi
    ;;
  yaml|yml)
    command -v yq >/dev/null 2>&1 || exit 0
    yq --inplace '.' "$FILE" 2>/dev/null
    ;;
esac
exit 0
