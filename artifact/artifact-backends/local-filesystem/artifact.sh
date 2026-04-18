#!/usr/bin/env bash
# local-filesystem backend — artifact.sh
#
# Backs: file, directory, artifact-template (schemes)
#
# URI formats:
#   file|local-filesystem/<relative-path>
#   directory|local-filesystem/<relative-path>
#   artifact-template|local-filesystem/<name>   (maps to artifact-templates/<name>.md under worktree root)
#
# Subcommands: create | get | update | list | delete | lock | release | status | progress | edges

set -euo pipefail

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH"; }
need jq

root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# ----- URI parsers -----

parse_uri() {
  # URI format: <scheme>|<backend>/<path>
  # Echoes "<abs>\n<rel>\n<scheme>" for a given URI.
  local u="$1"
  local scheme="${u%%|*}"
  local rest="${u#*|}"
  [ "$scheme" = "$u" ] && die "bad uri: $u (expected <scheme>|<backend>/<path>)"
  local backend="${rest%%/*}"
  local tail="${rest#*/}"
  [ "$backend" != "local-filesystem" ] && die "local-filesystem: bad backend in uri: $u"

  case "$scheme" in
    file|directory)
      case "$tail" in /*|*..*) die "rejected path: $tail" ;; "") die "empty path" ;; esac
      printf '%s/%s\n%s\n%s\n' "$(root)" "$tail" "$tail" "$scheme"
      ;;
    artifact-template)
      local name="$tail"
      case "$name" in */*|*..*|"") die "bad template name in uri: $u" ;; esac
      local rel="artifact-templates/$name.md"
      printf '%s/%s\n%s\n%s\n' "$(root)" "$rel" "$rel" "$scheme"
      ;;
    *) die "local-filesystem: scheme not supported: $scheme" ;;
  esac
}

edges_file() { printf '%s\n' "$1.edges.json"; }

read_edges() {
  local f=$(edges_file "$1")
  if [ -f "$f" ]; then jq -c '.edges // []' "$f"; else echo '[]'; fi
}

write_edges() {
  local abs="$1" edges="$2"
  local f=$(edges_file "$abs")
  mkdir -p "$(dirname "$f")"
  jq -n --argjson e "$edges" '{edges:$e}' > "$f"
}

# ----- Argv helpers -----

cmd="${1:?subcommand required}"; shift || true

args_scheme=""
new_argv=()
while [ $# -gt 0 ]; do
  case "$1" in
    --scheme) args_scheme="$2"; shift 2;;
    *) new_argv+=("$1"); shift;;
  esac
done
set -- "${new_argv[@]:-}"

# ----- Subcommands -----

case "$cmd" in
  get)
    uri=""
    while [ $# -gt 0 ]; do case "${1:-}" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r abs; read -r rel; read -r parsed_scheme; } < <(parse_uri "$uri")
    if [ "$parsed_scheme" = "directory" ]; then
      if [ ! -d "$abs" ]; then jq -n --arg uri "$uri" '{uri:$uri, exists:false, children:[], edges:[]}'; exit 0; fi
      children="[]"
      while IFS= read -r -d '' child; do
        crel="${child#$(root)/}"
        children=$(jq --arg uri "file|local-filesystem/$crel" '. + [$uri]' <<< "$children")
      done < <(find "$abs" -mindepth 1 -print0 2>/dev/null)
      edges=$(read_edges "$abs")
      jq -n --arg uri "$uri" --argjson c "$children" --argjson e "$edges" '{uri:$uri, exists:true, children:$c, edges:$e}'
    else
      if [ ! -f "$abs" ]; then jq -n --arg uri "$uri" '{uri:$uri, exists:false, edges:[]}'; exit 0; fi
      content=$(cat "$abs")
      edges=$(read_edges "$abs")
      jq -n --arg uri "$uri" --arg c "$content" --argjson e "$edges" '{uri:$uri, exists:true, content:$c, edges:$e}'
    fi
    ;;

  create)
    data_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in --data) data_path="$2"; shift 2;; *) shift;; esac; done
    data=$( [ "$data_path" = "-" ] && cat || cat "$data_path" )
    scheme="${args_scheme:-file}"
    case "$scheme" in
      file)
        rel=$(jq -r '.path // empty' <<< "$data")
        content=$(jq -r '.content // ""' <<< "$data")
        [ -n "$rel" ] || die "data.path required"
        abs="$(root)/$rel"
        mkdir -p "$(dirname "$abs")"
        printf '%s' "$content" > "$abs"
        uri="file|local-filesystem/$rel"
        ;;
      directory)
        rel=$(jq -r '.path // empty' <<< "$data")
        [ -n "$rel" ] || die "data.path required"
        abs="$(root)/$rel"
        mkdir -p "$abs"
        children=$(jq -c '.children // []' <<< "$data")
        edges=$(jq -c --argjson c "$children" '$c | map({target:., relation:"composed_of"})' <<< '{}')
        write_edges "$abs" "$edges"
        uri="directory|local-filesystem/$rel"
        ;;
      artifact-template)
        name=$(jq -r '.name // empty' <<< "$data")
        body=$(jq -r '.body // ""' <<< "$data")
        [ -n "$name" ] || die "data.name required"
        rel="artifact-templates/$name.md"
        abs="$(root)/$rel"
        mkdir -p "$(dirname "$abs")"
        tmp=$(mktemp)
        jq 'del(.body)' <<< "$data" | python3 -c '
import sys, json, yaml
d = json.load(sys.stdin)
print("---")
print(yaml.safe_dump(d, sort_keys=False, default_flow_style=False).rstrip())
print("---")
' > "$tmp"
        { cat "$tmp"; printf '\n'; printf '%s' "$body"; } > "$abs"
        rm -f "$tmp"
        uri="artifact-template|local-filesystem/$name"
        ;;
      *)
        die "scheme=$scheme not backed by local-filesystem"
        ;;
    esac
    jq -n --arg uri "$uri" '{uri:$uri, created:true}'
    ;;

  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in
      --uri) uri="$2"; shift 2;;
      --patch) patch_path="$2"; shift 2;;
      *) shift;; esac; done
    { read -r abs; read -r rel; read -r parsed_scheme; } < <(parse_uri "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    if [ "$parsed_scheme" = "directory" ]; then
      children=$(jq -c '.children // empty' <<< "$patch")
      if [ -n "$children" ] && [ "$children" != "null" ]; then
        edges=$(jq -c --argjson c "$children" '$c | map({target:., relation:"composed_of"})' <<< '{}')
        write_edges "$abs" "$edges"
      fi
    else
      new=$(jq -r '.content // empty' <<< "$patch")
      if [ -z "$new" ]; then die "patch.content required for $parsed_scheme"; fi
      mkdir -p "$(dirname "$abs")"
      printf '%s' "$new" > "$abs"
    fi
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;

  list)
    filter_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in --filter) filter_path="$2"; shift 2;; *) shift;; esac; done
    filter=$( [ -z "$filter_path" ] && echo '{}' || ( [ "$filter_path" = "-" ] && cat || cat "$filter_path" ))
    glob=$(jq -r '.glob // "**/*"' <<< "$filter")
    scheme="${args_scheme:-file}"
    r="$(root)"
    entries="[]"
    case "$scheme" in
      file)
        while IFS= read -r -d '' f; do
          rel="${f#$r/}"
          entries=$(jq --arg uri "file|local-filesystem/$rel" '. + [{uri:$uri}]' <<< "$entries")
        done < <(find "$r" -type f -path "$r/$glob" -print0 2>/dev/null || true)
        ;;
      directory)
        while IFS= read -r -d '' d; do
          rel="${d#$r/}"
          [ -z "$rel" ] && continue
          entries=$(jq --arg uri "directory|local-filesystem/$rel" '. + [{uri:$uri}]' <<< "$entries")
        done < <(find "$r" -type d -path "$r/$glob" -print0 2>/dev/null || true)
        ;;
      artifact-template)
        for f in "$r/artifact-templates"/*.md; do
          [ -f "$f" ] || continue
          name=$(basename "$f" .md)
          entries=$(jq --arg uri "artifact-template|local-filesystem/$name" '. + [{uri:$uri}]' <<< "$entries")
        done
        ;;
    esac
    jq --argjson es "$entries" '{entries:$es}' <<< '{}'
    ;;

  delete)
    uri=""; while [ $# -gt 0 ]; do case "${1:-}" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r abs; read -r rel; read -r parsed_scheme; } < <(parse_uri "$uri")
    if [ "$parsed_scheme" = "directory" ]; then
      rm -rf "$abs" "$(edges_file "$abs")"
    else
      rm -f "$abs" "$abs.lock" "$abs.progress.jsonl" "$(edges_file "$abs")"
    fi
    jq -n --arg uri "$uri" '{uri:$uri, deleted:true}'
    ;;

  lock)
    uri=""; owner=""; check=0
    while [ $# -gt 0 ]; do case "${1:-}" in
      --uri) uri="$2"; shift 2;;
      --owner) owner="$2"; shift 2;;
      --check) check=1; shift;;
      *) shift;; esac; done
    { read -r abs; read -r rel; read -r parsed_scheme; } < <(parse_uri "$uri")
    lock_file="$abs.lock"
    if [ "$check" = "1" ]; then
      if [ -f "$lock_file" ]; then
        held_by=$(cat "$lock_file" 2>/dev/null || echo "")
        if [ "$held_by" = "$owner" ]; then
          jq -n --arg o "$owner" '{held:true, current_owner:$o}'
        else
          jq -n --arg c "$held_by" '{held:false, current_owner:$c}'
        fi
      else
        jq -n '{held:false, current_owner:""}'
      fi
    else
      mkdir -p "$(dirname "$lock_file")"
      if [ -f "$lock_file" ]; then
        existing=$(cat "$lock_file" 2>/dev/null || echo "")
        if [ -n "$existing" ] && [ "$existing" != "$owner" ]; then
          jq -n --arg c "$existing" '{held:false, error:"lock-mismatch", current_owner:$c}'
          exit 4
        fi
      fi
      printf '%s' "$owner" > "$lock_file"
      jq -n --arg o "$owner" '{held:true, current_owner:$o}'
    fi
    ;;

  release)
    uri=""; owner=""
    while [ $# -gt 0 ]; do case "${1:-}" in
      --uri) uri="$2"; shift 2;;
      --owner) owner="$2"; shift 2;;
      *) shift;; esac; done
    { read -r abs; read -r rel; read -r parsed_scheme; } < <(parse_uri "$uri")
    lock_file="$abs.lock"
    if [ -f "$lock_file" ]; then
      existing=$(cat "$lock_file" 2>/dev/null || echo "")
      if [ -z "$existing" ] || [ "$existing" = "$owner" ]; then
        rm -f "$lock_file"
      fi
    fi
    jq -n '{released:true}'
    ;;

  status)
    uri=""; while [ $# -gt 0 ]; do case "${1:-}" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r abs; read -r rel; read -r parsed_scheme; } < <(parse_uri "$uri")
    if [ "$parsed_scheme" = "directory" ]; then
      if [ -d "$abs" ]; then jq -n --arg uri "$uri" '{uri:$uri, status:"complete"}'
      else jq -n --arg uri "$uri" '{uri:$uri, status:"unknown"}'; fi
    else
      if [ -f "$abs" ]; then jq -n --arg uri "$uri" '{uri:$uri, status:"complete"}'
      else jq -n --arg uri "$uri" '{uri:$uri, status:"unknown"}'; fi
    fi
    ;;

  progress)
    uri=""; append_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in
      --uri) uri="$2"; shift 2;;
      --append) append_path="$2"; shift 2;;
      *) shift;; esac; done
    { read -r abs; read -r rel; read -r parsed_scheme; } < <(parse_uri "$uri")
    log="$abs.progress.jsonl"
    if [ -z "$append_path" ]; then
      entries="[]"
      if [ -f "$log" ]; then
        entries=$(jq -s '.' "$log" 2>/dev/null || echo '[]')
      fi
      jq --argjson es "$entries" '{entries:$es}' <<< '{}'
    else
      entry=$( [ "$append_path" = "-" ] && cat || cat "$append_path" )
      mkdir -p "$(dirname "$log")"
      printf '%s\n' "$(jq -c . <<< "$entry")" >> "$log"
      jq -n '{appended:true}'
    fi
    ;;

  edges)
    uri=""
    while [ $# -gt 0 ]; do case "${1:-}" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r abs; read -r rel; read -r parsed_scheme; } < <(parse_uri "$uri")
    edges=$(read_edges "$abs")
    jq -n --arg uri "$uri" --argjson e "$edges" '{uri:$uri, edges:$e}'
    ;;

  *)
    die "unknown subcommand: $cmd"
    ;;
esac
