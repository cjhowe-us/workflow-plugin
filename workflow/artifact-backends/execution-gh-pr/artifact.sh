#!/usr/bin/env bash
# execution-gh-pr backend — artifact.sh
#
# Backs: execution (scheme)
# URI:   execution|execution-gh-pr/<owner>/<repo>/<pr-number>

set -euo pipefail

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH"; }
need gh
need jq

SUMMARY_TAG='<!-- wf:summary'
LEDGER_TAG='<!-- wf:ledger'
PROGRESS_TAG='<!-- wf:progress'

parse_uri() {
  local u="$1"
  local scheme="${u%%|*}"
  local rest="${u#*|}"
  [ "$scheme" = "execution" ] || die "execution-gh-pr: bad scheme: $scheme"
  local backend="${rest%%/*}"
  local tail="${rest#*/}"
  [ "$backend" = "execution-gh-pr" ] || die "execution-gh-pr: bad backend: $backend"
  # tail is <owner>/<repo>/<pr-number>
  local repo="${tail%/*}"
  local pr="${tail##*/}"
  [ -n "$repo" ] && [ -n "$pr" ] || die "bad execution uri: $u"
  printf '%s\n%s\n' "$repo" "$pr"
}

# Run-provider passes --scheme; consume it and strip from argv.
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
    { read -r repo; read -r pr; } < <(parse_uri "$uri")
    body=$(gh pr view "$pr" --repo "$repo" --json body,state,assignees,title,url 2>/dev/null) \
      || die "not-found"
    jq --arg uri "$uri" '. + {uri:$uri, edges:[]}' <<< "$body"
    ;;

  create)
    data_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in --data) data_path="$2"; shift 2;; *) shift;; esac; done
    [ -n "$data_path" ] || die "--data required"
    data=$( [ "$data_path" = "-" ] && cat || cat "$data_path" )
    title=$(jq -r '.title // "workflow execution"' <<< "$data")
    repo=$(jq -r '.repo // empty' <<< "$data")
    base=$(jq -r '.base // "main"' <<< "$data")
    head=$(jq -r '.head // empty' <<< "$data")
    summary=$(jq -r '.summary // ""' <<< "$data")
    [ -n "$repo" ] || die "repo required in data"
    [ -n "$head" ] || die "head branch required in data"
    body=$(printf '%s %s -->\n\n%s\n\n%s {"steps":[]} -->\n' \
      "$SUMMARY_TAG" "$(jq -c '{version:1, workflow:.workflow, workflow_inputs:.workflow_inputs, started_at:.started_at, status:"running"}' <<< "$data")" \
      "$summary" "$LEDGER_TAG")
    created=$(gh pr create --repo "$repo" --title "$title" --body "$body" --base "$base" --head "$head" --draft 2>&1) \
      || die "pr-create-failed: $created"
    num=$(printf '%s\n' "$created" | grep -oE '[0-9]+$' | tail -1)
    [ -n "$num" ] || die "could not parse PR number"
    jq -n --arg uri "execution|execution-gh-pr/$repo/$num" --arg url "$created" \
      '{uri:$uri, url:$url, status:"running"}'
    ;;

  update)
    uri=""; patch_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in
      --uri) uri="$2"; shift 2;;
      --patch) patch_path="$2"; shift 2;;
      *) shift;; esac; done
    [ -n "$uri" ] && [ -n "$patch_path" ] || die "--uri and --patch required"
    { read -r repo; read -r pr; } < <(parse_uri "$uri")
    patch=$( [ "$patch_path" = "-" ] && cat || cat "$patch_path" )
    existing=$(gh pr view "$pr" --repo "$repo" --json body --jq .body)
    new_body=$(jq -n --arg cur "$existing" --argjson p "$patch" '
      $cur + "\n\n<!-- wf:update -->\n" + ($p | tostring)
    ')
    gh pr edit "$pr" --repo "$repo" --body "$(printf '%s' "$new_body" | jq -r .)" >/dev/null
    jq -n --arg uri "$uri" '{uri:$uri, updated:true}'
    ;;

  list)
    filter_path=""; while [ $# -gt 0 ]; do case "${1:-}" in --filter) filter_path="$2"; shift 2;; *) shift;; esac; done
    filter=$( [ -z "$filter_path" ] && echo '{}' || ( [ "$filter_path" = "-" ] && cat || cat "$filter_path" ))
    repo=$(jq -r '.repo // empty' <<< "$filter")
    state=$(jq -r '.state // "open"' <<< "$filter")
    [ -n "$repo" ] || die "filter.repo required"
    results=$(gh pr list --repo "$repo" --state "$state" --search "in:body wf:summary" \
      --json number,title,state,assignees,url 2>/dev/null || echo '[]')
    jq --arg repo "$repo" '{entries: [.[] | {uri:("execution|execution-gh-pr/" + $repo + "/" + (.number|tostring)), title, state, assignees: (.assignees | map(.login)), url}]}' <<< "$results"
    ;;

  lock)
    uri=""; owner=""; check=0
    while [ $# -gt 0 ]; do case "${1:-}" in
      --uri) uri="$2"; shift 2;;
      --owner) owner="$2"; shift 2;;
      --check) check=1; shift;;
      *) shift;; esac; done
    { read -r repo; read -r pr; } < <(parse_uri "$uri")
    current=$(gh pr view "$pr" --repo "$repo" --json assignees --jq '.assignees[0].login // ""')
    if [ "$check" = "1" ]; then
      if [ "$current" = "$owner" ]; then
        jq -n --arg o "$owner" '{held:true, current_owner:$o}'
      else
        jq -n --arg c "$current" --arg o "$owner" '{held:false, current_owner:$c, requested_owner:$o}'
      fi
    else
      if [ -n "$current" ] && [ "$current" != "$owner" ]; then
        jq -n --arg c "$current" '{held:false, error:"lock-mismatch", current_owner:$c}'
        exit 4
      fi
      gh pr edit "$pr" --repo "$repo" --add-assignee "$owner" >/dev/null
      jq -n --arg o "$owner" '{held:true, current_owner:$o}'
    fi
    ;;

  release)
    uri=""; owner=""
    while [ $# -gt 0 ]; do case "${1:-}" in
      --uri) uri="$2"; shift 2;;
      --owner) owner="$2"; shift 2;;
      *) shift;; esac; done
    { read -r repo; read -r pr; } < <(parse_uri "$uri")
    current=$(gh pr view "$pr" --repo "$repo" --json assignees --jq '.assignees[0].login // ""')
    if [ -n "$current" ] && [ "$current" = "$owner" ]; then
      gh pr edit "$pr" --repo "$repo" --remove-assignee "$owner" >/dev/null || true
    fi
    jq -n '{released:true}'
    ;;

  status)
    uri=""; while [ $# -gt 0 ]; do case "${1:-}" in --uri) uri="$2"; shift 2;; *) shift;; esac; done
    { read -r repo; read -r pr; } < <(parse_uri "$uri")
    pr_data=$(gh pr view "$pr" --repo "$repo" --json state,isDraft,closedAt,mergedAt 2>/dev/null) \
      || die "not-found"
    status=$(jq -r '
      if .mergedAt != null then "complete"
      elif .state == "CLOSED" then "aborted"
      elif .isDraft then "running"
      elif .state == "OPEN" then "running"
      else "unknown" end
    ' <<< "$pr_data")
    jq --arg s "$status" --arg uri "$uri" '{status:$s, uri:$uri, at:now|todate} + .' <<< "$pr_data"
    ;;

  progress)
    uri=""; append_path=""
    while [ $# -gt 0 ]; do case "${1:-}" in
      --uri) uri="$2"; shift 2;;
      --append) append_path="$2"; shift 2;;
      *) shift;; esac; done
    { read -r repo; read -r pr; } < <(parse_uri "$uri")
    if [ -z "$append_path" ]; then
      comments=$(gh pr view "$pr" --repo "$repo" --json comments --jq '.comments[] | select(.body | startswith("<!-- wf:progress"))' 2>/dev/null || true)
      entries=$(printf '%s\n' "$comments" | jq -s '[ .[].body
        | capture("<!-- wf:progress (?<p>\\{.*?\\}) -->"; "s")
        | .p | fromjson ] // []' 2>/dev/null || echo '[]')
      jq --argjson es "$entries" '{entries:$es}' <<< '{}'
    else
      entry=$( [ "$append_path" = "-" ] && cat || cat "$append_path" )
      body="<!-- wf:progress $(jq -c . <<< "$entry") -->"$'\n'"$(jq -r '.summary // .step // "progress"' <<< "$entry")"
      gh pr comment "$pr" --repo "$repo" --body "$body" >/dev/null
      jq -n '{appended:true}'
    fi
    ;;

  *)
    die "unknown subcommand: $cmd"
    ;;
esac
