#!/usr/bin/env bash
# gh-branch — artifact.sh
# URIs: gh-branch:<owner>/<repo>/<branch>
set -euo pipefail
die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need gh; need jq

parse() {
  local rest="${1#gh-branch:}"; [ "$rest" = "$1" ] && die "bad uri: $1"
  local repo; local br
  # owner/repo/branch — branch may contain slashes
  owner_repo=$(printf '%s' "$rest" | cut -d/ -f1-2)
  br="${rest#$owner_repo/}"
  printf '%s\n%s\n' "$owner_repo" "$br"
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
    { read -r repo; read -r br; } < <(parse "$uri")
    gh api "/repos/$repo/branches/$br" | jq --arg uri "$uri" '. + {uri:$uri, kind:"gh-branch"}'
    ;;
  create)
    data=$(if [ $# -gt 0 ] && [ "$1" = "--data" ]; then [ "$2" = "-" ] && cat || cat "$2"; fi)
    repo=$(jq -r '.repo' <<< "$data"); br=$(jq -r '.branch' <<< "$data"); sha=$(jq -r '.sha' <<< "$data")
    [ -n "$sha" ] || die "data.sha required"
    gh api -X POST "/repos/$repo/git/refs" \
      -f ref="refs/heads/$br" -f sha="$sha" >/dev/null
    jq -n --arg uri "branch|gh-branch/$repo/$br" '{uri:$uri, created:true}'
    ;;
  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --patch) patch_path="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r br; } < <(parse "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    sha=$(jq -r '.sha' <<< "$patch"); force=$(jq -r '.force // false' <<< "$patch")
    args=(-f sha="$sha")
    [ "$force" = "true" ] && args+=(-F force=true)
    gh api -X PATCH "/repos/$repo/git/refs/heads/$br" "${args[@]}" >/dev/null
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;
  list)
    filter=$(if [ $# -gt 0 ] && [ "$1" = "--filter" ]; then [ "$2" = "-" ] && cat || cat "$2"; else echo '{}'; fi)
    repo=$(jq -r '.repo' <<< "$filter")
    gh api "/repos/$repo/branches" --paginate \
      | jq --arg repo "$repo" '{entries:[.[] | {uri:("branch|gh-branch/"+$repo+"/"+.name), sha:.commit.sha, protected}]}'
    ;;
  lock|release)
    jq -n '{held:true, note:"branches are ownerless refs"}'
    ;;
  status)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r br; } < <(parse "$uri")
    res=$(gh api "/repos/$repo/branches/$br" 2>/dev/null || echo '{}')
    jq --arg uri "$uri" '. + {uri:$uri, status: (if .name then "running" else "unknown" end)}' <<< "$res"
    ;;
  progress)
    jq -n '{entries:[]}'
    ;;
  *) die "unknown subcommand: $cmd" ;;
esac
