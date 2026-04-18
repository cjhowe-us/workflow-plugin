#!/usr/bin/env bash
# confluence-page — artifact.sh
# URIs: confluence-page:<space>/<id>
#
# Requires env: CONFLUENCE_BASE_URL, CONFLUENCE_USER, CONFLUENCE_TOKEN
set -euo pipefail

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need curl; need jq

require_env() {
  if [ -z "${!1:-}" ]; then die "$1 required"; fi
}

api() {
  require_env CONFLUENCE_BASE_URL
  require_env CONFLUENCE_USER
  require_env CONFLUENCE_TOKEN
  local method="$1" path="$2" body="${3:-}"
  local auth="$(printf '%s:%s' "$CONFLUENCE_USER" "$CONFLUENCE_TOKEN" | base64)"
  local args=(-sS -H "Authorization: Basic $auth" -H "Accept: application/json" -X "$method")
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" -d "$body")
  curl "${args[@]}" "${CONFLUENCE_BASE_URL%/}$path"
}

parse() {
  local rest="${1#confluence-page:}"
  [ "$rest" = "$1" ] && die "bad uri: $1"
  local space="${rest%/*}"; local id="${rest##*/}"
  printf '%s\n%s\n' "$space" "$id"
}

cmd="${1:?subcommand required}"; shift || true
case "$cmd" in
  get)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r space; read -r id; } < <(parse "$uri")
    res=$(api GET "/api/v2/pages/$id?body-format=storage")
    jq --arg uri "$uri" '. + {uri:$uri, kind:"confluence-page"}' <<< "$res"
    ;;
  create)
    data=$(if [ $# -gt 0 ] && [ "$1" = "--data" ]; then [ "$2" = "-" ] && cat || cat "$2"; fi)
    body=$(jq -c '{spaceId, title, body: {representation:"storage", value:(.content // "")}}' <<< "$data")
    res=$(api POST "/api/v2/pages" "$body")
    id=$(jq -r .id <<< "$res")
    space=$(jq -r '.spaceId // "?"' <<< "$data")
    jq -n --arg uri "confluence-page:$space/$id" --argjson r "$res" '{uri:$uri, created:true} + $r'
    ;;
  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --patch) patch_path="$2"; shift 2;; *) shift;; esac; done
    { read -r space; read -r id; } < <(parse "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    cur=$(api GET "/api/v2/pages/$id?body-format=storage")
    ver=$(jq -r '.version.number' <<< "$cur")
    body=$(jq -c --argjson v "$ver" --arg id "$id" --argjson cur "$cur" '
      {id:$id, status:"current",
       title: (.title // $cur.title),
       body: {representation:"storage", value:(.content // $cur.body.storage.value)},
       version: {number: ($v + 1)}}
    ' <<< "$patch")
    res=$(api PUT "/api/v2/pages/$id" "$body")
    if jq -e '.errors' <<< "$res" >/dev/null 2>&1; then
      msg=$(jq -r '.errors[0].title // "update-failed"' <<< "$res")
      die "$msg"
    fi
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;
  list)
    filter=$(if [ $# -gt 0 ] && [ "$1" = "--filter" ]; then [ "$2" = "-" ] && cat || cat "$2"; else echo '{}'; fi)
    space=$(jq -r '.space // empty' <<< "$filter"); [ -n "$space" ] || die "filter.space required"
    res=$(api GET "/api/v2/spaces/$space/pages?limit=50")
    jq --arg space "$space" '{entries:[.results[]? | {uri:("confluence-page:"+$space+"/"+.id), title, version:.version.number}]}' <<< "$res"
    ;;
  lock)
    uri=""; owner=""; check=0
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --owner) owner="$2"; shift 2;; --check) check=1; shift;; *) shift;; esac; done
    { read -r space; read -r id; } < <(parse "$uri")
    cur_owner=$(api GET "/api/v2/pages/$id" | jq -r '.ownerId // ""')
    if [ "$check" = "1" ]; then
      if [ "$cur_owner" = "$owner" ]; then jq -n --arg o "$owner" '{held:true, current_owner:$o}'
      else jq -n --arg c "$cur_owner" '{held:false, current_owner:$c}'; fi
    else
      # Setting owner requires separate API; may fail on restricted spaces
      res=$(api PUT "/api/v2/pages/$id/owner" "$(jq -n --arg o "$owner" '{ownerId:$o}')" || echo '{}')
      if jq -e '.errors' <<< "$res" >/dev/null 2>&1; then
        jq -n --arg c "$cur_owner" '{held:false, error:"owner-change-denied", current_owner:$c}'; exit 4
      fi
      jq -n --arg o "$owner" '{held:true, current_owner:$o}'
    fi
    ;;
  release)
    jq -n '{released:true, note:"confluence owner retained; no release semantic"}'
    ;;
  status)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r space; read -r id; } < <(parse "$uri")
    res=$(api GET "/api/v2/pages/$id")
    jq --arg uri "$uri" '. + {uri:$uri, status:
      (if .status == "current" then "running"
       elif .status == "archived" then "complete"
       else "unknown" end)}' <<< "$res"
    ;;
  progress)
    uri=""; append_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --append) append_path="$2"; shift 2;; *) shift;; esac; done
    { read -r space; read -r id; } < <(parse "$uri")
    if [ -z "$append_path" ]; then
      # Scrape <!-- wf:progress {...} --> comments out of storage-format body
      cur=$(api GET "/api/v2/pages/$id?body-format=storage")
      content=$(jq -r '.body.storage.value // ""' <<< "$cur")
      entries=$(printf '%s' "$content" \
        | grep -oE '<!-- wf:progress \{[^}]*\} -->' \
        | sed -E 's|<!-- wf:progress (.*) -->|\1|' \
        | jq -s '.' 2>/dev/null || echo '[]')
      jq --argjson es "$entries" '{entries:$es}' <<< '{}'
    else
      entry=$( [ "$append_path" = "-" ] && cat || cat "$append_path" )
      cur=$(api GET "/api/v2/pages/$id?body-format=storage")
      ver=$(jq -r '.version.number' <<< "$cur")
      body_text=$(jq -r '.body.storage.value' <<< "$cur")
      new_body=$(printf '%s\n<!-- wf:progress %s -->' "$body_text" "$(jq -c . <<< "$entry")")
      body=$(jq -c --arg id "$id" --argjson v "$ver" --arg b "$new_body" --argjson cur "$cur" '
        {id:$id, status:"current", title: $cur.title,
         body:{representation:"storage", value:$b},
         version:{number:($v + 1)}}' <<< "$cur")
      api PUT "/api/v2/pages/$id" "$body" >/dev/null
      jq -n '{appended:true}'
    fi
    ;;
  *) die "unknown subcommand: $cmd" ;;
esac
