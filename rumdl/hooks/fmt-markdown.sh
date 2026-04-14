#!/usr/bin/env bash
# PostToolUse: rumdl fmt for .md after Write / Edit / MultiEdit
INPUT=$(cat)

command -v rumdl >/dev/null 2>&1 || exit 0

fmt_if_md() {
  local FILE="$1"
  [[ -n "$FILE" && "$FILE" == *.md && -f "$FILE" ]] || return 0
  local OUTPUT RC
  OUTPUT=$(rumdl fmt "$FILE" 2>&1)
  RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "$OUTPUT"
  fi
}

while IFS= read -r FILE; do
  fmt_if_md "$FILE"
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
