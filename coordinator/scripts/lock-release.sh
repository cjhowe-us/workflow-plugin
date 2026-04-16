#!/usr/bin/env bash
# Release the coordinator lock on a pull request by stripping its HTML-comment
# marker from the PR body. Idempotent.
#
# Usage:
#   lock-release.sh --repo <owner/name> --pr <N>
#       Strip the marker regardless of owner. Used on graceful worker finish.
#
#   lock-release.sh --repo <owner/name> --pr <N> --expected-owner <string>
#       Strip only if the current marker's lock_owner matches. Used by the
#       SubagentStop hook to avoid stomping a concurrent worker's lock.
set -euo pipefail

REPO=""; PR=""; EXPECTED_OWNER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)            REPO="$2";           shift 2;;
    --pr)              PR="$2";             shift 2;;
    --expected-owner)  EXPECTED_OWNER="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
for v in REPO PR; do
  [[ -n "${!v}" ]] || { echo "$v required" >&2; exit 2; }
done

read_body() {
  gh pr view "$PR" --repo "$REPO" --json body -q '.body' 2>/dev/null || true
}

extract_marker_json() {
  printf '%s' "$1" | awk '
    /^<!-- coordinator = \{.*\} -->$/ {
      sub(/^<!-- coordinator = /, "")
      sub(/ -->$/, "")
      print
      exit
    }'
}

strip_marker() {
  printf '%s' "$1" | awk '
    !/^<!-- coordinator = \{.*\} -->$/ { print }'
}

body=$(read_body)
cur_json=$(extract_marker_json "$body")

# No marker — already released.
if [[ -z "$cur_json" ]]; then
  printf '{"released":false,"pr_number":%s,"repo":"%s","reason":"no-marker"}\n' "$PR" "$REPO"
  exit 0
fi

# Optional owner check — skip release if another worker now holds the lock.
if [[ -n "$EXPECTED_OWNER" ]]; then
  cur_owner=$(printf '%s' "$cur_json" | jq -r '.lock_owner // ""')
  if [[ "$cur_owner" != "$EXPECTED_OWNER" ]]; then
    printf '{"released":false,"pr_number":%s,"repo":"%s","reason":"owner-mismatch","current_owner":"%s"}\n' \
      "$PR" "$REPO" "$cur_owner"
    exit 0
  fi
fi

stripped=$(strip_marker "$body")
# Trim a single trailing blank line left behind by stripping the marker block.
stripped="${stripped%$'\n'}"

printf '%s\n' "$stripped" | gh pr edit "$PR" --repo "$REPO" --body-file - >/dev/null

printf '{"released":true,"pr_number":%s,"repo":"%s"}\n' "$PR" "$REPO"
