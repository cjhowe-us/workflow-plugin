#!/usr/bin/env bash
# document-filesystem backend — artifact.sh
#
# Backs: document (scheme)
# URIs:  document|document-filesystem/<relative-path>   (relative to git worktree root)

set -euo pipefail

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need jq

root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

parse_uri() {
  local u="$1"
  local scheme="${u%%|*}"
  local rest="${u#*|}"
  [ "$scheme" = "$u" ] && die "bad uri: $u (expected document|document-filesystem/<path>)"
  local backend="${rest%%/*}"
  local rel="${rest#*/}"
  [ "$scheme" = "document" ] || die "document-filesystem: scheme=$scheme not supported"
  [ "$backend" = "document-filesystem" ] || die "document-filesystem: bad backend: $backend"
  case "$rel" in /*|*..*) die "rejected path: $rel" ;; "") die "empty path" ;; esac
  printf '%s/%s\n%s\n' "$(root)" "$rel" "$rel"
}

cmd="${1:?subcommand required}"; shift || true
new_argv=()
while [ $# -gt 0 ]; do
  case "$1" in
    --scheme) shift 2;;
    *) new_argv+=("$1"); shift;;
  esac
done
set -- "${new_argv[@]:-}"

case "$cmd" in
  get)
    uri=""; while [ $# -gt 0 ]; do case "${1:-}" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r abs; read -r rel; } < <(parse_uri "$uri")
    if [ ! -f "$abs" ]; then jq -n --arg uri "$uri" '{uri:$uri, exists:false, edges:[]}'; exit 0; fi
    content=$(cat "$abs")
    jq -n --arg uri "$uri" --arg c "$content" '{uri:$uri, exists:true, body:$c, edges:[]}'
    ;;
  create)
    data_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in --data) data_path="$2"; shift 2;; *) shift;; esac; done
    data=$( [ "$data_path" = "-" ] && cat || cat "$data_path" )
    rel=$(jq -r '.path // empty' <<< "$data")
    body=$(jq -r '.body // ""' <<< "$data")
    fm=$(jq -c '.frontmatter // {}' <<< "$data")
    [ -n "$rel" ] || die "data.path required"
    abs="$(root)/$rel"
    mkdir -p "$(dirname "$abs")"
    if [ "$fm" != "{}" ] && [ -n "$fm" ]; then
      {
        printf -- '---\n'
        printf '%s' "$fm" | python3 -c 'import sys, json, yaml; print(yaml.safe_dump(json.load(sys.stdin), sort_keys=False).rstrip())'
        printf -- '\n---\n\n'
        printf '%s' "$body"
      } > "$abs"
    else
      printf '%s' "$body" > "$abs"
    fi
    jq -n --arg uri "document|document-filesystem/$rel" '{uri:$uri, created:true}'
    ;;
  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in
      --uri) uri="$2"; shift 2;;
      --patch) patch_path="$2"; shift 2;;
      *) shift;; esac; done
    { read -r abs; read -r rel; } < <(parse_uri "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    new=$(jq -r '.body // empty' <<< "$patch")
    [ -n "$new" ] || die "patch.body required"
    mkdir -p "$(dirname "$abs")"
    printf '%s' "$new" > "$abs"
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;
  list)
    filter_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in --filter) filter_path="$2"; shift 2;; *) shift;; esac; done
    filter=$( [ -z "$filter_path" ] && echo '{}' || ( [ "$filter_path" = "-" ] && cat || cat "$filter_path" ))
    glob=$(jq -r '.glob // "**/*.md"' <<< "$filter")
    r="$(root)"
    entries="[]"
    while IFS= read -r -d '' f; do
      rel="${f#$r/}"
      entries=$(jq --arg uri "document|document-filesystem/$rel" '. + [{uri:$uri}]' <<< "$entries")
    done < <(find "$r" -type f -path "$r/$glob" -print0 2>/dev/null || true)
    jq --argjson es "$entries" '{entries:$es}' <<< '{}'
    ;;
  delete)
    uri=""; while [ $# -gt 0 ]; do case "${1:-}" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r abs; read -r rel; } < <(parse_uri "$uri")
    rm -f "$abs"
    jq -n --arg uri "$uri" '{uri:$uri, deleted:true}'
    ;;
  status)
    uri=""; while [ $# -gt 0 ]; do case "${1:-}" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r abs; read -r rel; } < <(parse_uri "$uri")
    if [ -f "$abs" ]; then jq -n --arg uri "$uri" '{uri:$uri, status:"complete"}'
    else jq -n --arg uri "$uri" '{uri:$uri, status:"unknown"}'; fi
    ;;
  *)
    die "unknown subcommand: $cmd"
    ;;
esac
