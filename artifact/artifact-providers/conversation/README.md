# conversation — artifact scheme

A named log of turns with header metadata. Append-only semantics.

URIs: `conversation|<backend>/<slug>`.

Default backend: `session-memory` (persists to the user's cache dir as JSONL).
