#!/usr/bin/env bash
# os-notifications backend — artifact.sh
#
# Backs: notifications (scheme)
# URI:   notifications|os-notifications/session

set -euo pipefail

die() { printf '{"error":"%s"}\n' "$*"; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need jq

base="${XDG_RUNTIME_DIR:-/tmp}/artifact-${CLAUDE_SESSION_ID:-$PPID}"
mkdir -p "$base"
log="$base/notifications.jsonl"
cap=64

URI="notifications|os-notifications/session"

cmd="${1:?subcommand required}"; shift || true

case "$cmd" in
  get)
    [ -f "$log" ] || { jq -n --arg uri "$URI" '{uri:$uri, entries:[], edges:[]}'; exit 0; }
    jq -s --arg uri "$URI" '{uri:$uri, entries:., edges:[]}' "$log"
    ;;
  progress)
    append_path=""
    while [ $# -gt 0 ]; do case "$1" in
      --append) append_path="$2"; shift 2;;
      *) shift;; esac; done
    if [ -n "$append_path" ]; then
      entry=$( [ "$append_path" = "-" ] && cat || cat "$append_path" )
      printf '%s\n' "$(jq -c . <<< "$entry")" >> "$log"
      if [ -f "$log" ] && [ "$(wc -l <"$log")" -gt "$cap" ]; then
        tail -n "$cap" "$log" > "$log.tmp" && mv "$log.tmp" "$log"
      fi
      jq -n '{appended:true}'
    else
      [ -f "$log" ] || { jq -n '{entries:[]}'; exit 0; }
      jq -s '{entries:.}' "$log"
    fi
    ;;
  create)
    touch "$log"
    jq -n --arg uri "$URI" '{uri:$uri, created:true}'
    ;;
  update)
    jq -n '{updated:false, reason:"notifications are append-only; use progress --append"}'
    ;;
  list)
    jq -n --arg uri "$URI" '{entries:[{uri:$uri}]}'
    ;;
  status)
    jq -n --arg uri "$URI" '{uri:$uri, status:"running"}'
    ;;
  *)
    die "unknown subcommand: $cmd"
    ;;
esac
