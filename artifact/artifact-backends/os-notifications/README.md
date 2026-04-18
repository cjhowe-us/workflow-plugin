# os-notifications — artifact backend

Ephemeral, session-scoped log of notifications. Not durable — the backing file lives under `${XDG_RUNTIME_DIR:-/tmp}/artifact-${CLAUDE_SESSION_ID:-$PPID}/notifications.jsonl` and is capped at the most recent 64 entries.

Single well-known URI: `notifications|os-notifications/session`.
