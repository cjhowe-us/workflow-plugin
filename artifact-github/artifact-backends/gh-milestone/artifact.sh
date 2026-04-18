#!/usr/bin/env bash
# gh-milestone — artifact.sh
# URIs: gh-milestone:<owner>/<repo>/<number>
set -euo pipefail
die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need gh; need jq

parse() {
  local rest="${1#gh-milestone:}"; [ "$rest" = "$1" ] && die "bad uri: $1"
  local repo="${rest%/*}"; local n="${rest##*/}"
  printf '%s\n%s\n' "$repo" "$n"
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
    { read -r repo; read -r n; } < <(parse "$uri")
    gh api "/repos/$repo/milestones/$n" | jq --arg uri "$uri" '. + {uri:$uri, kind:"gh-milestone"}'
    ;;
  create)
    data=$(if [ $# -gt 0 ] && [ "$1" = "--data" ]; then [ "$2" = "-" ] && cat || cat "$2"; fi)
    repo=$(jq -r '.repo' <<< "$data")
    body=$(jq -c '{title, description: (.description // ""), due_on: (.due_on // null), state: (.state // "open")}' <<< "$data")
    res=$(gh api -X POST "/repos/$repo/milestones" --input - <<< "$body")
    num=$(jq -r .number <<< "$res")
    jq -n --arg uri "milestone|gh-milestone/$repo/$num" --argjson r "$res" '{uri:$uri, created:true} + $r'
    ;;
  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --patch) patch_path="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r n; } < <(parse "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    gh api -X PATCH "/repos/$repo/milestones/$n" --input - <<< "$(jq -c . <<< "$patch")" >/dev/null
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;
  list)
    filter=$(if [ $# -gt 0 ] && [ "$1" = "--filter" ]; then [ "$2" = "-" ] && cat || cat "$2"; else echo '{}'; fi)
    repo=$(jq -r '.repo' <<< "$filter"); state=$(jq -r '.state // "open"' <<< "$filter")
    gh api "/repos/$repo/milestones?state=$state" \
      | jq --arg repo "$repo" '{entries:[.[] | {uri:("milestone|gh-milestone/"+$repo+"/"+(.number|tostring)), title, state, due_on, url:.html_url}]}'
    ;;
  lock|release)
    jq -n '{held:true, note:"milestones have no owner lock"}'
    ;;
  status)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r n; } < <(parse "$uri")
    gh api "/repos/$repo/milestones/$n" | jq --arg uri "$uri" '. + {uri:$uri, status:
      (if .state == "open" then "running" else "complete" end)}'
    ;;
  progress)
    # Append to milestone description via PATCH.
    uri=""; append_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --append) append_path="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r n; } < <(parse "$uri")
    if [ -z "$append_path" ]; then
      jq -n '{entries:[]}'
    else
      entry=$( [ "$append_path" = "-" ] && cat || cat "$append_path" )
      cur=$(gh api "/repos/$repo/milestones/$n" --jq .description)
      new="$cur"$'\n'"<!-- wf:progress $(jq -c . <<< "$entry") -->"
      gh api -X PATCH "/repos/$repo/milestones/$n" -f description="$new" >/dev/null
      jq -n '{appended:true}'
    fi
    ;;
  *) die "unknown subcommand: $cmd" ;;
esac
