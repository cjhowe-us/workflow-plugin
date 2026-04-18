#!/usr/bin/env bash
# user-config backend — artifact.sh
#
# Backs: preferences (scheme)
# URIs:  preferences|user-config/<scope>  →  $ARTIFACT_CONFIG_DIR/preferences/<scope>.json

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/xdg.sh
. "$HERE/../../scripts/xdg.sh"

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need jq

base="$ARTIFACT_CONFIG_DIR/preferences"
mkdir -p "$base"

parse_uri() {
  local u="$1"
  local scheme="${u%%|*}"
  local rest="${u#*|}"
  [ "$scheme" = "$u" ] && die "bad uri: $u (expected preferences|user-config/<scope>)"
  local backend="${rest%%/*}"
  local scope="${rest#*/}"
  [ "$scheme" = "preferences" ] || die "user-config: scheme not supported: $scheme"
  [ "$backend" = "user-config" ] || die "user-config: bad backend: $backend"
  [ -n "$scope" ] || die "empty scope in uri: $u"
  case "$scope" in */*|*..*) die "rejected scope: $scope" ;; esac
  printf '%s' "$scope"
}

read_or_empty() { [ -f "$1" ] && cat "$1" || echo '{}'; }

cmd="${1:?subcommand required}"; shift || true

case "$cmd" in
  get)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    scope=$(parse_uri "$uri"); f="$base/$scope.json"
    jq --arg uri "$uri" '{uri:$uri, values:., edges:[]}' <<< "$(read_or_empty "$f")"
    ;;
  create)
    uri=""; data_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;;
      --data) data_path="$2"; shift 2;;
      *) shift;; esac; done
    [ -n "$uri" ] || die "--uri required"
    scope=$(parse_uri "$uri"); f="$base/$scope.json"
    data=$( [ "$data_path" = "-" ] && cat || cat "$data_path" )
    values=$(jq -c '.values // .' <<< "$data")
    printf '%s\n' "$values" > "$f"
    jq -n --arg uri "$uri" '{uri:$uri, created:true}'
    ;;
  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;;
      --patch) patch_path="$2"; shift 2;;
      *) shift;; esac; done
    [ -n "$uri" ] || die "--uri required"
    scope=$(parse_uri "$uri"); f="$base/$scope.json"
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    current=$(read_or_empty "$f")
    merged=$(jq -c -s '.[0] * .[1]' <(echo "$current") <(echo "$patch"))
    printf '%s\n' "$merged" > "$f"
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;
  list)
    entries="[]"
    for f in "$base"/*.json; do
      [ -f "$f" ] || continue
      scope=$(basename "$f" .json)
      entries=$(jq --arg uri "preferences|user-config/$scope" '. + [{uri:$uri}]' <<< "$entries")
    done
    jq --argjson es "$entries" '{entries:$es}' <<< '{}'
    ;;
  status)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    jq -n --arg uri "$uri" '{uri:$uri, status:"complete"}'
    ;;
  *)
    die "unknown subcommand: $cmd"
    ;;
esac
