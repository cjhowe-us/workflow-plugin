# preferences — artifact scheme

Key/value bags scoped by URI path.

URIs: `preferences|<backend>/<scope>`.

Scopes include `workspace`, `user`, `backends` (per-scheme backend defaults), `tutor`, …

Default backend: `user-config` (writes to the user's OS-standard config directory, resolved via `scripts/xdg.sh`).
