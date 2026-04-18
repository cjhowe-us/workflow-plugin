#!/usr/bin/env bash
# gh-issue provider — artifact.sh
# URIs: gh-issue:<owner>/<repo>/<number>
set -euo pipefail

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need gh; need jq

parse_uri() {
  local u="$1"; local scheme="${u%%|*}"; local after="${u#*|}"
  local backend="${after%%/*}"; local rest="${after#*/}"
  [ "$rest" = "$u" ] && die "bad uri: $u"
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
    { read -r repo; read -r n; } < <(parse_uri "$uri")
    gh issue view "$n" --repo "$repo" --json number,title,body,state,assignees,labels,url,closedAt \
      | jq --arg uri "$uri" '. + {uri:$uri, kind:"gh-issue"}'
    ;;
  create)
    data_path=""; while [ $# -gt 0 ]; do case "$1" in --data) data_path="$2"; shift 2;; *) shift;; esac; done
    data=$( [ "$data_path" = "-" ] && cat || cat "$data_path" )
    repo=$(jq -r '.repo' <<< "$data"); title=$(jq -r '.title' <<< "$data")
    body=$(jq -r '.body // ""' <<< "$data")
    url=$(gh issue create --repo "$repo" --title "$title" --body "$body" 2>&1) || die "issue-create-failed"
    num=$(echo "$url" | grep -oE '[0-9]+$' | tail -1)
    jq -n --arg uri "issue|gh-issue/$repo/$num" --arg url "$url" '{uri:$uri, url:$url, created:true}'
    ;;
  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;;
      --patch) patch_path="$2"; shift 2;;
      *) shift;; esac; done
    { read -r repo; read -r n; } < <(parse_uri "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    args=(--repo "$repo")
    t=$(jq -r '.title // empty' <<< "$patch"); [ -n "$t" ] && args+=(--title "$t")
    b=$(jq -r '.body // empty' <<< "$patch");  [ -n "$b" ] && args+=(--body "$b")
    gh issue edit "$n" "${args[@]}" >/dev/null
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;
  list)
    filter_path=""; while [ $# -gt 0 ]; do case "$1" in --filter) filter_path="$2"; shift 2;; *) shift;; esac; done
    filter=$( [ -z "$filter_path" ] && echo '{}' || ( [ "$filter_path" = "-" ] && cat || cat "$filter_path" ))
    repo=$(jq -r '.repo' <<< "$filter"); state=$(jq -r '.state // "open"' <<< "$filter")
    gh issue list --repo "$repo" --state "$state" --json number,title,state,url \
      | jq --arg repo "$repo" '{entries:[.[] | {uri:("issue|gh-issue/"+$repo+"/"+(.number|tostring)), title, state, url}]}'
    ;;
  lock)
    uri=""; owner=""; check=0
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;;
      --owner) owner="$2"; shift 2;;
      --check) check=1; shift;;
      *) shift;; esac; done
    { read -r repo; read -r n; } < <(parse_uri "$uri")
    current=$(gh issue view "$n" --repo "$repo" --json assignees --jq '.assignees[0].login // ""')
    if [ "$check" = "1" ]; then
      if [ "$current" = "$owner" ]; then jq -n --arg o "$owner" '{held:true, current_owner:$o}'
      else jq -n --arg c "$current" '{held:false, current_owner:$c}'; fi
    else
      if [ -n "$current" ] && [ "$current" != "$owner" ]; then
        jq -n --arg c "$current" '{held:false, error:"lock-mismatch", current_owner:$c}'; exit 4
      fi
      gh issue edit "$n" --repo "$repo" --add-assignee "$owner" >/dev/null
      jq -n --arg o "$owner" '{held:true, current_owner:$o}'
    fi
    ;;
  release)
    uri=""; owner=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;;
      --owner) owner="$2"; shift 2;;
      *) shift;; esac; done
    { read -r repo; read -r n; } < <(parse_uri "$uri")
    gh issue edit "$n" --repo "$repo" --remove-assignee "$owner" >/dev/null 2>&1 || true
    jq -n '{released:true}'
    ;;
  status)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r n; } < <(parse_uri "$uri")
    gh issue view "$n" --repo "$repo" --json state,stateReason,closedAt \
      | jq --arg uri "$uri" '. + {uri:$uri, status:
          (if .state == "OPEN" then "running"
           elif .stateReason == "NOT_PLANNED" then "aborted"
           else "complete" end)}'
    ;;
  progress)
    uri=""; append_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;;
      --append) append_path="$2"; shift 2;;
      *) shift;; esac; done
    { read -r repo; read -r n; } < <(parse_uri "$uri")
    if [ -z "$append_path" ]; then
      comments=$(gh issue view "$n" --repo "$repo" --json comments --jq '.comments[] | select(.body | startswith("<!-- wf:progress")) | .body' 2>/dev/null || true)
      entries=$(printf '%s\n' "$comments" | while read -r b; do
        [ -z "$b" ] && continue
        printf '%s\n' "$b" | sed -nE 's|^<!-- wf:progress (.*) -->.*|\1|p'
      done | jq -s '.')
      jq --argjson es "${entries:-[]}" '{entries:$es}' <<< '{}'
    else
      entry=$( [ "$append_path" = "-" ] && cat || cat "$append_path" )
      body="<!-- wf:progress $(jq -c . <<< "$entry") -->"$'\n'"$(jq -r '.summary // .message // "progress"' <<< "$entry")"
      gh issue comment "$n" --repo "$repo" --body "$body" >/dev/null
      jq -n '{appended:true}'
    fi
    ;;
  *)
    die "unknown subcommand: $cmd"
    ;;
esac
