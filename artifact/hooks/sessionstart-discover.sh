#!/usr/bin/env bash
# sessionstart-discover.sh
#
# Build a registry of installed artifact providers (kinds), backends,
# templates, and workflows from every installed plugin plus
# workspace / user / override scopes.
#
# Output: $ARTIFACT_CACHE_DIR/registry.json (single JSON).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/xdg.sh
. "$HERE/../scripts/xdg.sh"

mkdir -p "$ARTIFACT_CACHE_DIR"
registry="$ARTIFACT_CACHE_DIR/registry.json"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Collect scope roots in precedence order:
#   override  → $CWD/.artifact-override
#   workspace → <repo-root>/.claude
#   user      → $HOME/.claude
#   plugin    → every installed plugin root
scopes_json='[]'
add_scope() {
  local root="$1" scope="$2"
  [ -d "$root" ] || return 0
  scopes_json=$(printf '%s' "$scopes_json" | jq --arg p "$root" --arg s "$scope" '. + [{scope:$s, root:$p}]')
}

cwd="$(pwd)"
add_scope "$cwd/.artifact-override" override

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo_root" ] && add_scope "$repo_root/.claude" workspace
add_scope "$HOME/.claude" user

if [ -n "${CLAUDE_PLUGIN_DIRS:-}" ]; then
  IFS=':' read -r -a dirs <<< "$CLAUDE_PLUGIN_DIRS"
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for plugin in "$d"/*; do
      [ -d "$plugin" ] || continue
      add_scope "$plugin" plugin
    done
  done
fi

# Also include the plugin we live in (artifact itself) as a plugin scope.
plugin_root="$(cd "$HERE/.." && pwd)"
add_scope "$plugin_root" plugin

# Dev convenience: also scan sibling directories of the artifact plugin
# (`artifact-github`, `artifact-documents`, `workflow`, etc.) when
# CLAUDE_PLUGIN_DIRS isn't set.
if [ -z "${CLAUDE_PLUGIN_DIRS:-}" ]; then
  parent="$(cd "$plugin_root/.." && pwd)"
  for sibling in "$parent"/*; do
    [ -d "$sibling" ] || continue
    [ "$sibling" = "$plugin_root" ] && continue
    case "$(basename "$sibling")" in
      artifact*|workflow*) add_scope "$sibling" plugin ;;
    esac
  done
fi

entries='[]'

collect() {
  # Aggregate by catching subshell output
  entries=$(printf '%s' "$entries" | jq --arg s "$1" --arg p "$2" --arg t "$3" --argjson fm "$4" \
    '. + [{entry_type:$t, scope:$s, path:$p, name:$fm.name, description:$fm.description, contract_version:($fm.contract_version // null), backs_schemes:($fm.backs_schemes // null), scheme:($fm.scheme // null)}]')
}

extract_yaml_frontmatter() {
  awk '
    BEGIN { in_fm=0 }
    /^---[[:space:]]*$/ {
      if (in_fm == 0) { in_fm=1; next } else { exit }
    }
    in_fm==1 { print }
  ' | python3 -c 'import sys,yaml,json; d=yaml.safe_load(sys.stdin.read()) or {}; print(json.dumps({"name":d.get("name"),"description":d.get("description"),"contract_version":d.get("contract_version"),"scheme":d.get("scheme")}))' 2>/dev/null || echo '{}'
}

walk_scope() {
  local scope="$1" root="$2"

  # artifact-providers (kinds)
  for path in "$root"/artifact-providers/*/manifest.json; do
    [ -f "$path" ] || continue
    fm=$(cat "$path")
    name=$(jq -r '.name // empty' <<< "$fm")
    [ -n "$name" ] && collect "$scope" "$path" "artifact-provider" "$fm"
  done

  # artifact-backends
  for path in "$root"/artifact-backends/*/manifest.json; do
    [ -f "$path" ] || continue
    fm=$(cat "$path")
    name=$(jq -r '.name // empty' <<< "$fm")
    [ -n "$name" ] && collect "$scope" "$path" "artifact-backend" "$fm"
  done

  # artifact-templates (single-file shape)
  for path in "$root"/artifact-templates/*.md "$root"/artifact-templates/*.json "$root"/artifact-templates/*.yaml; do
    [ -f "$path" ] || continue
    fm=$(extract_yaml_frontmatter < "$path")
    name=$(jq -r '.name // empty' <<< "$fm")
    [ -n "$name" ] && collect "$scope" "$path" "artifact-template" "$fm"
  done

  # workflows (Claude Code skills under skills/workflows/)
  for path in "$root"/skills/workflows/*/SKILL.md; do
    [ -f "$path" ] || continue
    fm=$(extract_yaml_frontmatter < "$path")
    name=$(jq -r '.name // empty' <<< "$fm")
    [ -n "$name" ] && collect "$scope" "$path" "workflow" "$fm"
  done
}

# Walk each scope and accumulate into $entries.
# The scopes_json list is walked in-process (not via a subshell)
# so $entries survives.
count=$(jq 'length' <<< "$scopes_json")
i=0
while [ "$i" -lt "$count" ]; do
  scope=$(jq -r ".[$i].scope" <<< "$scopes_json")
  root=$(jq -r ".[$i].root"  <<< "$scopes_json")
  walk_scope "$scope" "$root"
  i=$((i + 1))
done

jq -n --argjson entries "$entries" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{generated_at:$at, entries:$entries}' > "$registry"

exit 0
