#!/usr/bin/env bash
# Acquire the coordinator lock on a pull request by splicing an HTML-comment
# marker into the PR body.
#
# Marker format (single line, appended to the body):
#   <!-- coordinator = {"lock_owner":"...","lock_expires_at":"...","blocked_by":[...]} -->
#
# Usage:
#   lock-acquire.sh --repo <owner/name> --pr <N> --owner <string> --expires-at <YYYY-MM-DDTHH:MM:SSZ>
#
# Exits 0 on success, 1 on race (another owner holds a non-expired lock),
# 2 on usage error.
set -euo pipefail

REPO=""; PR=""; OWNER=""; EXPIRY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)       REPO="$2";   shift 2;;
    --pr)         PR="$2";     shift 2;;
    --owner)      OWNER="$2";  shift 2;;
    --expires-at) EXPIRY="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
for v in REPO PR OWNER EXPIRY; do
  [[ -n "${!v}" ]] || { echo "$v required" >&2; exit 2; }
done

now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

read_body() {
  gh pr view "$PR" --repo "$REPO" --json body -q '.body' 2>/dev/null || true
}

# Extract the single-line marker's JSON payload (empty string if no marker).
extract_marker_json() {
  printf '%s' "$1" | awk '
    /^<!-- coordinator = \{.*\} -->$/ {
      sub(/^<!-- coordinator = /, "")
      sub(/ -->$/, "")
      print
      exit
    }'
}

# Strip the marker line from a body, preserving everything else.
strip_marker() {
  printf '%s' "$1" | awk '
    !/^<!-- coordinator = \{.*\} -->$/ { print }'
}

body=$(read_body)
cur_json=$(extract_marker_json "$body")
cur_owner=""; cur_expiry=""; cur_blocked_by="[]"
if [[ -n "$cur_json" ]]; then
  cur_owner=$(printf '%s' "$cur_json" | jq -r '.lock_owner // ""')
  cur_expiry=$(printf '%s' "$cur_json" | jq -r '.lock_expires_at // ""')
  cur_blocked_by=$(printf '%s' "$cur_json" | jq -c '.blocked_by // []')
fi

# Abort if another owner holds a non-expired lock.
if [[ -n "$cur_owner" && -n "$cur_expiry" && "$cur_expiry" > "$now_iso" && "$cur_owner" != "$OWNER" ]]; then
  echo "raced: held by $cur_owner until $cur_expiry" >&2
  exit 1
fi

# Build the fresh marker, preserving existing blocked_by.
new_json=$(jq -c -n \
  --arg owner "$OWNER" \
  --arg expiry "$EXPIRY" \
  --argjson blocked "$cur_blocked_by" \
  '{lock_owner: $owner, lock_expires_at: $expiry, blocked_by: $blocked}')
new_marker="<!-- coordinator = ${new_json} -->"

# Splice: strip any old marker, append fresh one.
stripped=$(strip_marker "$body")
# Ensure one blank line between user content and marker if body is non-empty.
if [[ -n "$stripped" ]]; then
  new_body="${stripped%$'\n'}"$'\n\n'"${new_marker}"
else
  new_body="${new_marker}"
fi

printf '%s\n' "$new_body" | gh pr edit "$PR" --repo "$REPO" --body-file - >/dev/null

# Race mitigation: 100-500ms backoff, re-read, verify ownership.
sleep "0.$(printf '%03d' $((RANDOM % 400 + 100)))"

verify_json=$(extract_marker_json "$(read_body)")
ver_owner=""
[[ -n "$verify_json" ]] && ver_owner=$(printf '%s' "$verify_json" | jq -r '.lock_owner // ""')

if [[ "$ver_owner" != "$OWNER" ]]; then
  # Release our half-write.
  "$(dirname "$0")/lock-release.sh" --repo "$REPO" --pr "$PR" >/dev/null 2>&1 || true
  echo "raced: overwritten by $ver_owner after write" >&2
  exit 1
fi

printf '{"acquired":true,"owner":"%s","expires_at":"%s","at":"%s","pr_number":%s,"repo":"%s"}\n' \
  "$OWNER" "$EXPIRY" "$now_iso" "$PR" "$REPO"
