#!/usr/bin/env bash
# gh-tag — artifact.sh
# URIs: gh-tag:<owner>/<repo>/<tag>
set -euo pipefail
die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need gh; need jq

parse() {
  local rest="${1#gh-tag:}"; [ "$rest" = "$1" ] && die "bad uri: $1"
  local repo="${rest%/*}"; local tag="${rest##*/}"
  printf '%s\n%s\n' "$repo" "$tag"
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
    { read -r repo; read -r tag; } < <(parse "$uri")
    gh api "/repos/$repo/git/ref/tags/$tag" | jq --arg uri "$uri" '. + {uri:$uri, kind:"gh-tag"}'
    ;;
  create)
    data=$(if [ $# -gt 0 ] && [ "$1" = "--data" ]; then [ "$2" = "-" ] && cat || cat "$2"; fi)
    repo=$(jq -r '.repo' <<< "$data"); tag=$(jq -r '.tag' <<< "$data"); sha=$(jq -r '.sha' <<< "$data")
    [ -n "$sha" ] || die "data.sha required"
    gh api -X POST "/repos/$repo/git/refs" \
      -f ref="refs/tags/$tag" -f sha="$sha" >/dev/null
    jq -n --arg uri "tag|gh-tag/$repo/$tag" '{uri:$uri, created:true}'
    ;;
  update)
    # Move a tag (force-update). Rarely appropriate; support it but note it.
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --patch) patch_path="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r tag; } < <(parse "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    sha=$(jq -r '.sha' <<< "$patch")
    gh api -X PATCH "/repos/$repo/git/refs/tags/$tag" -f sha="$sha" -F force=true >/dev/null
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;
  list)
    filter=$(if [ $# -gt 0 ] && [ "$1" = "--filter" ]; then [ "$2" = "-" ] && cat || cat "$2"; else echo '{}'; fi)
    repo=$(jq -r '.repo' <<< "$filter")
    gh api "/repos/$repo/git/refs/tags" --paginate \
      | jq --arg repo "$repo" '{entries:[.[] | {uri:("tag|gh-tag/"+$repo+"/"+ (.ref | sub("refs/tags/"; ""))), sha:.object.sha}]}'
    ;;
  lock|release)
    jq -n '{held:true, note:"tags are one-shot; no owner lock"}'
    ;;
  status)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    jq -n --arg uri "$uri" '{uri:$uri, status:"complete"}'
    ;;
  progress)
    if [ $# -gt 0 ] && [ "$1" = "--append" ] || [ "${2:-}" = "--append" ]; then
      jq -n '{appended:false, reason:"tags do not support progress events"}'
    else
      jq -n '{entries:[]}'
    fi
    ;;
  *) die "unknown subcommand: $cmd" ;;
esac
