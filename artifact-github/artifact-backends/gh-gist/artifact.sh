#!/usr/bin/env bash
# gh-gist — artifact.sh
# URIs: gh-gist:<gist-id>
set -euo pipefail
die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need gh; need jq

id_of() {
  local u="$1"; local id="${u#gist|gh-gist/}"
  [ "$id" = "$u" ] && die "bad uri: $u"
  printf '%s' "$id"
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
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    id=$(id_of "$uri")
    gh api "/gists/$id" | jq --arg uri "$uri" '. + {uri:$uri, kind:"gh-gist"}'
    ;;
  create)
    data=$(if [ $# -gt 0 ] && [ "$1" = "--data" ]; then [ "$2" = "-" ] && cat || cat "$2"; fi)
    public=$(jq -r '.public // false' <<< "$data")
    desc=$(jq -r '.description // ""' <<< "$data")
    # data.files is a map of filename→content
    args=(-X POST /gists -f description="$desc" -F "public=$public")
    # Pipe files as JSON body
    body=$(jq -c '{description, public, files: (.files // {} | map_values({content:.}))}' <<< "$data")
    res=$(gh api -X POST /gists --input - <<< "$body")
    id=$(jq -r .id <<< "$res")
    jq -n --arg uri "gist|gh-gist/$id" --argjson r "$res" '{uri:$uri, created:true, url:$r.html_url}'
    ;;
  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --patch) patch_path="$2"; shift 2;; *) shift;; esac; done
    id=$(id_of "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    body=$(jq -c '{description: (.description // null), files: (.files // {} | map_values({content:.}))}' <<< "$patch")
    gh api -X PATCH "/gists/$id" --input - <<< "$body" >/dev/null
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;
  list)
    filter=$(if [ $# -gt 0 ] && [ "$1" = "--filter" ]; then [ "$2" = "-" ] && cat || cat "$2"; else echo '{}'; fi)
    # Lists only the authenticated user's gists.
    gh api /gists --paginate \
      | jq '{entries:[.[] | {uri:("gist|gh-gist/"+.id), description, public, url:.html_url}]}'
    ;;
  lock)
    # Gists have a single owner (the creator). lock --check compares the
    # authenticated user to the gist owner.
    uri=""; owner=""; check=0
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --owner) owner="$2"; shift 2;; --check) check=1; shift;; *) shift;; esac; done
    id=$(id_of "$uri")
    current=$(gh api "/gists/$id" --jq .owner.login 2>/dev/null || echo "")
    if [ "$check" = "1" ] || true; then
      if [ "$current" = "$owner" ]; then
        jq -n --arg o "$owner" '{held:true, current_owner:$o}'
      else
        jq -n --arg c "$current" '{held:false, current_owner:$c, note:"gists lock to the creator; transfer requires fork"}'
        [ "$check" = "1" ] && exit 0 || exit 4
      fi
    fi
    ;;
  release)
    jq -n '{released:true, note:"gist ownership is permanent; this is a no-op"}'
    ;;
  status)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    id=$(id_of "$uri")
    gh api "/gists/$id" >/dev/null 2>&1 \
      && jq -n --arg uri "$uri" '{uri:$uri, status:"complete"}' \
      || jq -n --arg uri "$uri" '{uri:$uri, status:"unknown"}'
    ;;
  progress)
    # Progress for gists isn't meaningful; we support append by adding a
    # `progress.jsonl` file inside the gist.
    uri=""; append_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --append) append_path="$2"; shift 2;; *) shift;; esac; done
    id=$(id_of "$uri")
    if [ -z "$append_path" ]; then
      cur=$(gh api "/gists/$id" --jq '.files["progress.jsonl"].content // ""' 2>/dev/null || echo "")
      entries=$(printf '%s' "$cur" | jq -s -R 'split("\n") | map(select(length>0)) | map(fromjson)')
      jq --argjson es "$entries" '{entries:$es}' <<< '{}'
    else
      entry=$( [ "$append_path" = "-" ] && cat || cat "$append_path" )
      cur=$(gh api "/gists/$id" --jq '.files["progress.jsonl"].content // ""' 2>/dev/null || echo "")
      new="$cur"$'\n'"$(jq -c . <<< "$entry")"
      body=$(jq -n --arg c "$new" '{files: {"progress.jsonl": {content:$c}}}')
      gh api -X PATCH "/gists/$id" --input - <<< "$body" >/dev/null
      jq -n '{appended:true}'
    fi
    ;;
  *) die "unknown subcommand: $cmd" ;;
esac
