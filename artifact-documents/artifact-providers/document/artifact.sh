#!/usr/bin/env bash
# document provider — artifact.sh
# URIs: document:<backend>/<id>   where backend is file-local | confluence-page | ...
#
# Thin delegator: extracts <backend>, rewrites the URI to <backend>:<id>,
# and shells out to run-provider.sh for that backend. Every subcommand is
# forwarded verbatim.
set -euo pipefail

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }

# Locate run-provider.sh from the core plugin (CLAUDE_PLUGIN_DIRS).
find_runner() {
  if [ -n "${CLAUDE_PLUGIN_DIRS:-}" ]; then
    IFS=':' read -r -a dirs <<< "$CLAUDE_PLUGIN_DIRS"
    for d in "${dirs[@]}"; do
      for p in "$d"/workflow "$d"/*/workflow; do
        [ -x "$p/scripts/run-provider.sh" ] && { printf '%s' "$p/scripts/run-provider.sh"; return 0; }
      done
    done
  fi
  # Fallback for dev checkouts: siblings of this plugin. $0 lives at
  # `<plugin>/artifact-providers/<name>/artifact.sh`, so three levels up
  # lands at the plugins-siblings directory (where `workflow/` lives).
  local here
  here="$(cd "$(dirname "$0")/../../.." && pwd)"
  local cand="$here/workflow/scripts/run-provider.sh"
  [ -x "$cand" ] && { printf '%s' "$cand"; return 0; }
  die "run-provider.sh not found; is the workflow plugin installed?"
}

rewrite_uri() {
  # document:<backend>/<id>  →  <backend>:<id>
  local u="$1"; local rest="${u#document:}"
  [ "$rest" = "$u" ] && die "bad document uri: $u"
  local backend="${rest%%/*}"; local id="${rest#*/}"
  printf '%s:%s\n%s\n' "$backend" "$id" "$backend"
}

runner=$(find_runner)

cmd="${1:?subcommand required}"; shift || true

# Validate the subcommand against the artifact-contract surface before
# forwarding. Keeps conformance tooling happy and catches typos early.
case "$cmd" in
  get|create|update|list|lock|release|status|progress) ;;
  *) die "unknown subcommand: $cmd" ;;
esac

# Rewrite --uri flag if present
new_args=()
seen_uri=""
while [ $# -gt 0 ]; do
  case "$1" in
    --uri)
      { read -r new_uri; read -r backend; } < <(rewrite_uri "$2")
      seen_uri="$backend"
      new_args+=(--uri "$new_uri")
      shift 2
      ;;
    *) new_args+=("$1"); shift ;;
  esac
done

# If the subcommand doesn't take a uri (e.g. create, list), we need to
# resolve the backend from the incoming data. Default to file-local.
if [ -z "$seen_uri" ]; then
  case "$cmd" in
    create|list)
      seen_uri="file-local"
      ;;
  esac
fi

[ -n "$seen_uri" ] || die "cannot determine backend for subcommand $cmd"

exec "$runner" "$seen_uri" "" "$cmd" "${new_args[@]}"
