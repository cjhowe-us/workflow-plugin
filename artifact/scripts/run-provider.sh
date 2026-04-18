#!/usr/bin/env bash
# run-provider.sh
#
# Dispatch an artifact subcommand to the right backend.
#
# Usage:
#   run-provider.sh <URI-or-scheme> <subcommand> [--backend <name>] [args...]
#
# URI format: <scheme>|<backend>/<path>
#   e.g.   file|local-filesystem/hello.txt
#          preferences|user-config/user
#          artifact-template|local-filesystem/design-document
#
# Resolution:
#   1. If first arg is a URI (contains `|`), backend is in the URI.
#   2. Else, a --backend <name> later in argv overrides everything.
#   3. Else, look up preferences at $ARTIFACT_CONFIG_DIR/preferences/backends.json
#      → backends.<scheme>.default.
#   4. Else, if exactly one backend backs this scheme, use it and persist as default.
#   5. Else, fail with a clear error asking the /artifact skill to prompt.
#
# Execs:
#   <plugin>/artifact-backends/<backend>/artifact.sh <subcommand> --scheme <scheme> [args...]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./xdg.sh
. "$HERE/xdg.sh"

die() { printf '{"error":"%s"}\n' "$*" >&2; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need jq

registry="$ARTIFACT_CACHE_DIR/registry.json"

ensure_registry() {
  if [ ! -f "$registry" ]; then
    local hook="$HERE/../hooks/sessionstart-discover.sh"
    if [ -x "$hook" ]; then "$hook" >/dev/null 2>&1 || true; fi
  fi
  [ -f "$registry" ] || die "registry not found: $registry"
}

scheme_from_uri() {
  local u="$1"
  case "$u" in *\|*/*)
    printf '%s' "${u%%|*}"
    ;;
  *) return 1 ;;
  esac
}

backend_from_uri() {
  local u="$1"
  case "$u" in *\|*/*)
    local rest="${u#*|}"
    printf '%s' "${rest%%/*}"
    ;;
  *) return 1 ;;
  esac
}

resolve_backend_for_scheme() {
  local scheme="$1" override="$2"
  ensure_registry
  if [ -n "$override" ]; then
    printf '%s' "$override"
    return 0
  fi

  local pref_file="$ARTIFACT_CONFIG_DIR/preferences/backends.json"
  if [ -f "$pref_file" ]; then
    local chosen
    chosen=$(jq -r --arg s "$scheme" '.[$s].default // empty' "$pref_file" 2>/dev/null || true)
    if [ -n "$chosen" ]; then
      printf '%s' "$chosen"
      return 0
    fi
  fi

  local backends
  backends=$(jq -r --arg s "$scheme" '
    .entries
    | map(select(.entry_type == "artifact-backend" and (((.backs_schemes // []) | index($s)) != null)))
    | .[].name
  ' "$registry" 2>/dev/null)

  local count
  count=$(printf '%s\n' "$backends" | grep -c . || true)
  if [ "$count" = "1" ]; then
    local only="$backends"
    mkdir -p "$ARTIFACT_CONFIG_DIR/preferences"
    local current='{}'
    [ -f "$pref_file" ] && current=$(cat "$pref_file")
    printf '%s\n' "$(jq --arg s "$scheme" --arg b "$only" '. * {($s):{default:$b}}' <<< "$current")" > "$pref_file"
    printf '%s' "$only"
    return 0
  fi

  if [ "$count" = "0" ]; then
    die "no backend installed for scheme=$scheme"
  fi
  die "multiple backends for scheme=$scheme ($backends). Set preferences://user-config/backends.$scheme.default, or pass --backend <name>."
}

backend_path_for() {
  local name="$1"
  ensure_registry
  jq -r --arg n "$name" '
    .entries
    | map(select(.entry_type == "artifact-backend" and .name == $n))
    | .[0].path // empty
  ' "$registry" 2>/dev/null
}

first="${1:?URI-or-scheme required}"
subcommand="${2:?subcommand required}"
shift 2 || true

backend_override=""
passthrough_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --backend) backend_override="$2"; shift 2;;
    *) passthrough_args+=("$1"); shift;;
  esac
done

if backend=$(backend_from_uri "$first" 2>/dev/null); then
  scheme=$(scheme_from_uri "$first")
  if [ "${#passthrough_args[@]}" -eq 0 ]; then
    passthrough_args=(--uri "$first")
  else
    passthrough_args=(--uri "$first" "${passthrough_args[@]}")
  fi
else
  scheme="$first"
  backend=$(resolve_backend_for_scheme "$scheme" "$backend_override")
fi

passthrough_args=(--scheme "$scheme" "${passthrough_args[@]}")

manifest=$(backend_path_for "$backend")
[ -n "$manifest" ] || die "backend not found in registry: $backend"

script_dir=$(dirname "$manifest")
script="$script_dir/artifact.sh"
[ -x "$script" ] || die "backend artifact.sh not executable: $script"

if [ "${#passthrough_args[@]}" -eq 0 ]; then
  exec "$script" "$subcommand"
else
  exec "$script" "$subcommand" "${passthrough_args[@]}"
fi
