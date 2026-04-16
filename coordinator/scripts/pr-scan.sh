#!/usr/bin/env bash
# Scan one or more GitHub repositories for coordinator-managed pull requests
# and emit one JSON record per PR on stdout. A PR is in scope when it is open,
# draft, and carries a `phase:<name>` label.
#
# Usage:
#   pr-scan.sh <owner/name> [<owner/name>...]
#
# Record shape (one per line):
#   {
#     "repo": "owner/name",
#     "number": 12,
#     "state": "open",
#     "is_draft": true,
#     "head_ref_name": "coordinator/specify-login",
#     "phase": "specify",
#     "lock_owner": "macbook:sess1:worker-1" | "",
#     "lock_expires_at": "2026-04-16T18:45:00Z" | "",
#     "blocked_by": [42, 57]
#   }
set -euo pipefail

(( $# > 0 )) || { echo "usage: pr-scan.sh <owner/name> [<owner/name>...]" >&2; exit 2; }

if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "gh and jq are required" >&2
  exit 2
fi

extract_marker_json() {
  printf '%s' "$1" | awk '
    /^<!-- coordinator = \{.*\} -->$/ {
      sub(/^<!-- coordinator = /, "")
      sub(/ -->$/, "")
      print
      exit
    }'
}

for repo in "$@"; do
  prs=$(gh pr list --repo "$repo" --state open --limit 100 \
          --json number,state,isDraft,headRefName,labels,body)
  echo "$prs" | jq -c '.[]' | while IFS= read -r pr; do
    phase=$(echo "$pr" | jq -r '
      [.labels[].name | select(startswith("phase:"))] | .[0] // "" | sub("^phase:"; "")
    ')
    [[ -z "$phase" ]] && continue

    body=$(echo "$pr" | jq -r '.body // ""')
    marker_json=$(extract_marker_json "$body")
    lock_owner=""; lock_expires_at=""; blocked_by="[]"
    if [[ -n "$marker_json" ]]; then
      lock_owner=$(printf '%s' "$marker_json" | jq -r '.lock_owner // ""')
      lock_expires_at=$(printf '%s' "$marker_json" | jq -r '.lock_expires_at // ""')
      blocked_by=$(printf '%s' "$marker_json" | jq -c '.blocked_by // []')
    fi

    jq -n \
      --arg repo "$repo" \
      --argjson pr "$pr" \
      --arg phase "$phase" \
      --arg lock_owner "$lock_owner" \
      --arg lock_expires_at "$lock_expires_at" \
      --argjson blocked_by "$blocked_by" \
      '{
         repo: $repo,
         number: $pr.number,
         state: ($pr.state // "" | ascii_downcase),
         is_draft: ($pr.isDraft // false),
         head_ref_name: ($pr.headRefName // null),
         phase: $phase,
         lock_owner: $lock_owner,
         lock_expires_at: $lock_expires_at,
         blocked_by: $blocked_by
      }' | jq -c '.'
  done
done
