#!/usr/bin/env bash
# workflow-conformance.sh
#
# Validate a workflow directory against the workflow contract.
#
# Layout:
#   <workflow-dir>/
#     SKILL.md      (Claude Code skill: name, description in frontmatter + prose)
#     manifest.json (structured workflow state: inputs, outputs, graph, transitions)
#
# Exits 0 on pass, non-zero on violation with line-level errors on stderr.
#
# Usage:
#   workflow-conformance.sh <path-to-workflow-dir-OR-SKILL.md>

set -euo pipefail

arg="${1:?path to workflow directory or SKILL.md required}"
if [ -d "$arg" ]; then
  dir="$arg"
elif [ -f "$arg" ]; then
  dir="$(dirname "$arg")"
else
  echo "not-found: $arg" >&2; exit 2
fi

skill="$dir/SKILL.md"
manifest="$dir/manifest.json"
fail=0
warn() { echo "workflow-conformance: $*" >&2; fail=1; }

[ -f "$skill" ]    || warn "missing SKILL.md"
[ -f "$manifest" ] || warn "missing manifest.json"

# SKILL.md frontmatter: name + description.
if [ -f "$skill" ]; then
  python3 - "$skill" <<'PY' || fail=1
import sys, re, yaml, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
if not m:
    print(f"workflow-conformance: bad frontmatter in {p}", file=sys.stderr); sys.exit(1)
try:
    fm = yaml.safe_load(m.group(1)) or {}
except yaml.YAMLError as e:
    print(f"workflow-conformance: invalid YAML in {p}: {e}", file=sys.stderr); sys.exit(1)
for k in ("name", "description"):
    if k not in fm:
        print(f"workflow-conformance: SKILL.md frontmatter missing `{k}`", file=sys.stderr); sys.exit(1)
sys.exit(0)
PY
fi

# manifest.json: structured workflow state.
if [ -f "$manifest" ]; then
  python3 - "$manifest" <<'PY' || fail=1
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
try:
    m = json.loads(p.read_text())
except json.JSONDecodeError as e:
    print(f"workflow-conformance: invalid JSON in {p}: {e}", file=sys.stderr); sys.exit(1)

errors = []

if "contract_version" not in m:
    errors.append("manifest.json: missing `contract_version`")

graph = m.get("graph") or {}
steps = graph.get("steps") or []
if not isinstance(steps, list) or not steps:
    errors.append("manifest.graph.steps: must be a non-empty list")

ids = []
for i, s in enumerate(steps):
    if not isinstance(s, dict):
        errors.append(f"manifest.graph.steps[{i}]: must be a mapping"); continue
    if "id" not in s:
        errors.append(f"manifest.graph.steps[{i}]: missing `id`"); continue
    if s["id"] in ids:
        errors.append(f"manifest.graph.steps[{i}]: duplicate id `{s['id']}`")
    ids.append(s["id"])

trs = graph.get("transitions") or []
tids = []
for j, t in enumerate(trs):
    if not isinstance(t, dict):
        errors.append(f"manifest.graph.transitions[{j}]: must be a mapping"); continue
    for k in ("id", "from", "to"):
        if k not in t:
            errors.append(f"manifest.graph.transitions[{j}]: missing `{k}`")
    if t.get("from") and t["from"] not in ids:
        errors.append(f"manifest.graph.transitions[{j}]: from `{t['from']}` not in steps")
    if t.get("to") and t["to"] not in ids:
        errors.append(f"manifest.graph.transitions[{j}]: to `{t['to']}` not in steps")
    tids.append(t.get("id"))

for k, b in enumerate(m.get("dynamic_branches") or []):
    if b.get("step") not in ids:
        errors.append(f"manifest.dynamic_branches[{k}]: step `{b.get('step')}` not in steps")
    for tid in (b.get("transitions") or []):
        if tid not in tids:
            errors.append(f"manifest.dynamic_branches[{k}]: transition `{tid}` not in transitions")

for e in errors:
    print(f"workflow-conformance: {e}", file=sys.stderr)

sys.exit(1 if errors else 0)
PY
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "workflow-conformance: $dir OK"
exit 0
