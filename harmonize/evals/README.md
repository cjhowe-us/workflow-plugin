# Workflow sanity evals

Structural, data-driven sanity checks for the workflow repo. Deterministic, no LLM, no flakes. Runs
in under a second.

## Usage

```bash
harmonize/evals/run.sh
```

Exits 0 regardless of result. The summary section reports totals and lists every failure.

## Scope

| Suite | What it checks |
|-------|----------------|
| agents | frontmatter parses, required fields present, `name` matches filename, description within length bounds, `model` matches allow-list, tools non-empty, body has H1 |
| hook scripts | script exists, executable bit set, shebang present, shellcheck clean |
| hooks.json (Claude plugins) | valid JSON, every command resolves with `${CLAUDE_PLUGIN_ROOT}` |
| hooks.json (Cursor plugins) | `hooks/hooks.cursor.json` per plugin: valid JSON, `command` paths relative to plugin root (`./hooks/...`) |
| plugin manifests | valid JSON, required fields (`name`, `version`, `description`) present |

## Data-driven

Test data lives in [`cases.yaml`](cases.yaml). The runner reads it with `yq` and dispatches to
bounded check functions. To add coverage, edit the data — not the runner.

Examples:

1. **Add a new agent directory.** Append another glob under `.agents.globs`.
2. **Tighten the description length bound.** Change `.agents.description_max_length`.
3. **Add another hooks file.** Append to `.hooks_json.files` (Claude) or `.hooks_json_cursor_plugins.files` (Cursor).

## Prereqs

| Tool | Purpose |
|------|---------|
| `yq` | Parse `cases.yaml` and agent frontmatter |
| `jq` | Parse `hooks.json` and `plugin.json` |
| `shellcheck` | Lint hook scripts (optional; skipped if absent) |
