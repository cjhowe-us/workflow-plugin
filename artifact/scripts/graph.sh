#!/usr/bin/env bash
# Graph traversal over artifact edges.
#
# Subcommands (stubs; implementations land in later steps):
#   expand --uri <U> [--relation R] [--depth N]
#     BFS walk outward from U. Returns {"nodes":[...], "edges":[...]}.
#   path --from A --to B [--max-depth N]
#     Shortest path via repeated provider edges/find calls.
#   dot --uri <U> [--depth N]
#     Emit Graphviz DOT for visualization.
#
# Uses ARTIFACT_CACHE_DIR/graph/ to memoize walks; invalidation keyed on
# each node's updated_at as returned by its provider get call.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./xdg.sh
. "$HERE/xdg.sh"

die() { printf '{"error":%s}\n' "$(jq -Rs . <<<"$1")" >&2; exit 1; }

cmd="${1:-}"
shift || true

case "$cmd" in
  expand|path|dot)
    die "graph $cmd not yet implemented"
    ;;
  "")
    die "usage: graph.sh {expand|path|dot} [args]"
    ;;
  *)
    die "unknown subcommand: $cmd"
    ;;
esac
