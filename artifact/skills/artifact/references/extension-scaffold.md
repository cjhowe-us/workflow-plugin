# extension-scaffold

Scaffolds a sibling Claude Code plugin that extends the `workflow` plugin. The target plugin can
contribute any mix of:

- workflows (under `skills/workflows/<name>/SKILL.md`)
- artifact templates (under `skills/artifact-templates/<name>/{TEMPLATE.md,template.json}`)
- artifact providers (under `artifact-providers/<name>/{manifest.json,artifact.sh}`)

## Inputs

- `name` — plugin name (kebab-case), becomes directory name.
- `path` — parent directory to create it under.
- `description` — one-line plugin description for plugin.json and README.
- `contributes` — one or more of `workflows`, `templates`, `providers`.
- `depends_on` — other plugins in the marketplace this one needs (`workflow-github`,
  `workflow-documents`,...).

## Output

```text
<path>/<name>/
  .claude-plugin/plugin.json
  README.md
  skills/
    workflows/           (if contributes workflows)
    artifact-templates/  (if contributes templates; these are workflows too)
  artifact-providers/    (if contributes providers; plain scripts, not skills)
```

Providers are not skills — they live at the plugin root under `artifact-providers/<name>/` with
`manifest.json` + `artifact.sh`. Workflows and artifact templates are skills (carrying
workflow-contract frontmatter) under `skills/`. The README stubs the contribution list, dependency
list, and installation instructions. Subtrees are empty — the user runs `/workflow author` afterward
to create the first workflow or template; providers are hand-authored using the `artifact-contract`
skill as the guide.

## Registration

After scaffold, the new plugin directory must be listed in the marketplace's
`.claude-plugin/marketplace.json` entry for discovery. The scaffold skill prints the exact snippet
to append; the user commits it to their marketplace repo themselves.

## Conformance

Scaffolded plugins pass the workflow-conformance and provider-conformance test suites out of the box
— empty contribution sets are valid.
