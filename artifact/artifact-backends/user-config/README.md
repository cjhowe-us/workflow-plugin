# user-config — artifact backend

Persists preferences under the user's OS-standard config directory:

- Linux: `${XDG_CONFIG_HOME:-~/.config}/artifact/preferences/<scope>.json`
- macOS: `~/Library/Application Support/artifact/preferences/<scope>.json`
- Windows: `%APPDATA%\artifact\preferences\<scope>.json`

Each scope (e.g. `user`, `workspace`, `backends`) is a separate JSON file. Updates merge into existing JSON (RFC 7396 JSON Merge Patch semantics).
