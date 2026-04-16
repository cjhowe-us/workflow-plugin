#!/usr/bin/env bash
# Extend the lock_expires_at on a pull request's marker. Caller must already
# hold the lock; the current lock_owner is verified before each heartbeat
# (prevents stomping if a human or stale-reclaim overwrote it).
#
# Usage:
#   lock-heartbeat.sh --repo <owner/name> --pr <N> \
#       --expected-owner <string> --expires-at <YYYY-MM-DDTHH:MM:SSZ>
#
# Exits 0 on success, 1 if the lock has been stolen (owner mismatch or
# marker missing), 2 on usage error.
set -euo pipefail

REPO=""; PR=""; OWNER=""; EXPIRY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)            REPO="$2";   shift 2;;
    --pr)              PR="$2";     shift 2;;
    --expected-owner)  OWNER="$2";  shift 2;;
    --expires-at)      EXPIRY="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
for v in REPO PR OWNER EXPIRY; do
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
if [[ -z "$cur_json" ]]; then
  echo "stolen: marker missing on PR #$PR" >&2
  exit 1
fi

cur_owner=$(printf '%s' "$cur_json" | jq -r '.lock_owner // ""')
if [[ "$cur_owner" != "$OWNER" ]]; then
  echo "stolen: current owner is '$cur_owner' (expected '$OWNER')" >&2
  exit 1
fi

cur_blocked_by=$(printf '%s' "$cur_json" | jq -c '.blocked_by // []')

new_json=$(jq -c -n \
  --arg owner "$OWNER" \
  --arg expiry "$EXPIRY" \
  --argjson blocked "$cur_blocked_by" \
  '{lock_owner: $owner, lock_expires_at: $expiry, blocked_by: $blocked}')
new_marker="<!-- coordinator = ${new_json} -->"

stripped=$(strip_marker "$body")
if [[ -n "$stripped" ]]; then
  new_body="${stripped%$'\n'}"$'\n\n'"${new_marker}"
else
  new_body="${new_marker}"
fi

printf '%s\n' "$new_body" | gh pr edit "$PR" --repo "$REPO" --body-file - >/dev/null

printf '{"heartbeat":"ok","expires_at":"%s","pr_number":%s,"repo":"%s"}\n' "$EXPIRY" "$PR" "$REPO"
