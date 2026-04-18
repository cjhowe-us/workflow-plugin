#!/usr/bin/env bash
# render-doc-template.sh
#
# Shared helper used by the eight document-template `instantiate.sh`
# entry scripts. Reads JSON inputs on stdin, expects argv[1] to be the
# template directory.
#
# Behavior:
#   1. Load manifest.json + template.md from the template directory.
#   2. Validate required inputs (also validated by instantiate-template.sh
#      upstream; this is a belt-and-braces check).
#   3. Render `{{ name }}` and `{{ slug(name) }}` placeholders using the
#      supplied inputs.
#   4. Resolve the output path from manifest.output_path using the same
#      placeholder engine.
#   5. Dispatch to the `document` provider via the artifact plugin's
#      `run-provider.sh` with the rendered content + resolved path.
#   6. Emit the provider's create response on stdout.
set -euo pipefail

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need jq

template_dir="${1:?template directory required}"
manifest="$template_dir/manifest.json"
shell="$template_dir/template.md"
[ -f "$manifest" ] || die "missing manifest.json"
[ -f "$shell" ] || die "missing template.md"

inputs="$(cat)"
[ -n "$inputs" ] || die "no JSON input on stdin"

# Slugify (kebab-case, alnum + hyphens, lowercase)
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

# Render a single field expression like `{{ title }}` or `{{ slug(title) }}`.
# Returns the expanded string.
render() {
  local text="$1"
  # Handle {{ slug(X) }} first
  while [[ "$text" =~ \{\{[[:space:]]*slug\(([a-zA-Z_][a-zA-Z0-9_]*)\)[[:space:]]*\}\} ]]; do
    local key="${BASH_REMATCH[1]}"
    local raw
    raw=$(jq -r --arg k "$key" '.[$k] // ""' <<< "$inputs")
    local slug
    slug=$(slugify "$raw")
    text="${text//${BASH_REMATCH[0]}/$slug}"
  done
  # Then plain {{ X }}
  while [[ "$text" =~ \{\{[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\}\} ]]; do
    local key="${BASH_REMATCH[1]}"
    local val
    val=$(jq -r --arg k "$key" '.[$k] // ""' <<< "$inputs")
    text="${text//${BASH_REMATCH[0]}/$val}"
  done
  printf '%s' "$text"
}

# Resolve the output path from the manifest's output_path template
out_path_tmpl=$(jq -r '.output_path // ""' "$manifest")
[ -n "$out_path_tmpl" ] || die "manifest.output_path required"
out_path=$(render "$out_path_tmpl")

# Render the template body
body=$(render "$(cat "$shell")")

# Dispatch to the document provider via the artifact plugin's run-provider.sh
# Locate run-provider.sh — walk up looking for a sibling `artifact/` plugin
find_runner() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local cand="$here/artifact/scripts/run-provider.sh"
  [ -x "$cand" ] && { printf '%s' "$cand"; return 0; }
  die "artifact plugin not found at $cand"
}
runner=$(find_runner)

payload=$(jq -n --arg path "$out_path" --arg content "$body" '{path:$path, content:$content}')
response=$(printf '%s' "$payload" | "$runner" document "" create --data -)
printf '%s\n' "$response"
