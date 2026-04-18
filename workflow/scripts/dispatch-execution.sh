#!/usr/bin/env bash
# dispatch-execution.sh
#
# Shared helper for workflow-shape artifact templates. Each template's
# `instantiate.sh` execs this script with the template directory as argv[1].
#
# Behavior:
#   1. Read JSON inputs on stdin (validated upstream by instantiate-template.sh).
#   2. Resolve the workflow name from the template's manifest.json.
#   3. Read the workflow definition from TEMPLATE.md (YAML frontmatter is the
#      workflow-contract declaration; body is human docs).
#   4. Call the `execution` provider's `create` with:
#        {
#          "workflow":        "<name>",
#          "workflow_inputs": <inputs>,
#          "parent_execution": "<uri>|null",
#          "owner":           "<gh-user>"
#        }
#   5. Emit the provider's response on stdout (expected to include `uri`).
set -euo pipefail

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need jq

template_dir="${1:?template directory required}"
manifest="$template_dir/manifest.json"
[ -f "$manifest" ] || die "missing manifest.json"

inputs="$(cat)"
[ -n "$inputs" ] || inputs='{}'

wf_name=$(jq -r '.name' "$manifest")

# Locate artifact plugin's run-provider.sh
find_runner() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local cand="$here/artifact/scripts/run-provider.sh"
  [ -x "$cand" ] && { printf '%s' "$cand"; return 0; }
  die "artifact plugin not found at $cand"
}
runner=$(find_runner)

# Derive owner (GH user) + parent_execution from inputs if present
parent=$(jq -r '.parent_execution // empty' <<< "$inputs")
owner=$(jq -r '.owner // empty' <<< "$inputs")
if [ -z "$owner" ]; then
  owner=$(gh api user --jq .login 2>/dev/null || echo "")
fi

payload=$(jq -n --arg w "$wf_name" --argjson i "$inputs" --arg o "$owner" --arg p "$parent" '
  {
    workflow:          $w,
    workflow_inputs:   $i,
    owner:             (if $o == "" then null else $o end),
    parent_execution:  (if $p == "" then null else $p end)
  }
')

response=$(printf '%s' "$payload" | "$runner" execution "" create --data -)
printf '%s\n' "$response"
