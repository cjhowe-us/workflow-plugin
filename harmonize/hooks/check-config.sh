#!/usr/bin/env bash
# PostToolUse hook: format/check JSON, TOML, YAML files
# Write/Edit: tool_input.file_path. MultiEdit: tool_input.edits[].file_path (or .path).
INPUT=$(cat)

format_one() {
  local FILE="$1"
  [ -n "$FILE" ] || return 0
  [ -f "$FILE" ] || return 0

  local EXT="${FILE##*.}"

  case "$EXT" in
    toml)
      command -v taplo >/dev/null 2>&1 || return 0
      taplo fmt "$FILE" 2>/dev/null || true
      ;;
    json)
      command -v jq >/dev/null 2>&1 || return 0
      TMP=$(mktemp)
      if jq --sort-keys . "$FILE" >"$TMP" 2>/dev/null; then
        mv "$TMP" "$FILE"
      else
        rm -f "$TMP"
      fi
      ;;
    yaml|yml)
      command -v yq >/dev/null 2>&1 || return 0
      yq --inplace '.' "$FILE" 2>/dev/null || true
      ;;
  esac
}

while IFS= read -r FILE; do
  format_one "$FILE"
done < <(
  echo "$INPUT" | jq -r '
    (.tool_input // {})
    | [
        (.file_path // ""),
        (.edits // [] | map(.file_path // .path // "") | .[])
      ]
    | map(select(length > 0))
    | unique
    | .[]
  '
)

exit 0
