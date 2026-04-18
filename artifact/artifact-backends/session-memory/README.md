# session-memory — artifact backend

Persists conversations as JSONL files in the user's cache dir:

- Linux: `~/.cache/artifact/conversations/<slug>.jsonl`
- macOS: `~/Library/Caches/artifact/conversations/<slug>.jsonl`
- Windows: `%LOCALAPPDATA%\artifact\conversations\<slug>.jsonl`

First line is the header metadata (JSON object). Subsequent lines are turn objects, appended via `update --patch {turn: {...}}`.
