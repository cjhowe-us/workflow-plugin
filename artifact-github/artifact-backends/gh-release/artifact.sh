#!/usr/bin/env bash
# gh-release provider — artifact.sh
# URIs: gh-release:<owner>/<repo>/<tag>
set -euo pipefail
die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need gh; need jq

parse() {
  local rest="${1#gh-release:}"; [ "$rest" = "$1" ] && die "bad uri: $1"
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
    gh release view "$tag" --repo "$repo" --json name,tagName,body,isDraft,isPrerelease,publishedAt,url \
      | jq --arg uri "$uri" '. + {uri:$uri, kind:"gh-release"}'
    ;;
  create)
    data=$(if [ $# -gt 0 ] && [ "$1" = "--data" ]; then [ "$2" = "-" ] && cat || cat "$2"; fi)
    repo=$(jq -r '.repo' <<< "$data"); tag=$(jq -r '.tag' <<< "$data")
    title=$(jq -r '.title // .tag' <<< "$data"); body=$(jq -r '.body // ""' <<< "$data")
    draft=$(jq -r '.draft // false' <<< "$data")
    args=(create "$tag" --repo "$repo" --title "$title" --notes "$body")
    [ "$draft" = "true" ] && args+=(--draft)
    gh release "${args[@]}" >/dev/null
    jq -n --arg uri "release|gh-release/$repo/$tag" '{uri:$uri, created:true}'
    ;;
  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --patch) patch_path="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r tag; } < <(parse "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    args=(--repo "$repo")
    t=$(jq -r '.title // empty' <<< "$patch"); [ -n "$t" ] && args+=(--title "$t")
    b=$(jq -r '.body // empty' <<< "$patch");  [ -n "$b" ] && args+=(--notes "$b")
    gh release edit "$tag" "${args[@]}" >/dev/null
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;
  list)
    filter=$(if [ $# -gt 0 ] && [ "$1" = "--filter" ]; then [ "$2" = "-" ] && cat || cat "$2"; else echo '{}'; fi)
    repo=$(jq -r '.repo // empty' <<< "$filter"); [ -n "$repo" ] || die "filter.repo required"
    gh release list --repo "$repo" --json name,tagName,isDraft,publishedAt,url --limit 50 \
      | jq --arg repo "$repo" '{entries:[.[] | {uri:("release|gh-release/"+$repo+"/"+.tagName), name, tagName, url}]}'
    ;;
  lock|release)
    jq -n '{held:true, note:"releases are one-shot; lock is a no-op"}'
    ;;
  status)
    uri=""; while [ $# -gt 0 ]; do case "$1" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r tag; } < <(parse "$uri")
    gh release view "$tag" --repo "$repo" --json isDraft,publishedAt \
      | jq --arg uri "$uri" '. + {uri:$uri, status:
          (if .isDraft then "running" elif .publishedAt then "complete" else "unknown" end)}'
    ;;
  progress)
    # Append notes to release body by rewriting the wf:notes section.
    uri=""; append_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --uri) uri="$2"; shift 2;; --append) append_path="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r tag; } < <(parse "$uri")
    if [ -z "$append_path" ]; then
      jq -n '{entries:[]}'
    else
      entry=$( [ "$append_path" = "-" ] && cat || cat "$append_path" )
      cur=$(gh release view "$tag" --repo "$repo" --json body --jq .body 2>/dev/null || echo "")
      line="<!-- wf:notes $(jq -c . <<< "$entry") -->"
      new="$cur"$'\n'"$line"
      gh release edit "$tag" --repo "$repo" --notes "$new" >/dev/null
      jq -n '{appended:true}'
    fi
    ;;
  *) die "unknown subcommand: $cmd" ;;
esac
