"""Workflow conformance validator.

A workflow directory must contain:

- ``workflow.md`` with YAML frontmatter carrying `name` + `description`.
- ``manifest.json`` with the typed DSL: contract_version, graph.steps,
  graph.transitions, optional dynamic_branches.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


@dataclass
class Result:
    target: Path
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


_FRONTMATTER = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def check(directory: Path) -> Result:
    r = Result(target=directory)
    wf_file = directory / "workflow.md"
    manifest_file = directory / "manifest.json"

    if not wf_file.is_file():
        r.errors.append("missing workflow.md")
    if not manifest_file.is_file():
        r.errors.append("missing manifest.json")

    if wf_file.is_file():
        _check_frontmatter(wf_file, r)
    if manifest_file.is_file():
        _check_manifest(manifest_file, r)

    return r


def _check_frontmatter(path: Path, r: Result) -> None:
    text = path.read_text()
    m = _FRONTMATTER.match(text)
    if not m:
        r.errors.append(f"workflow.md: missing or malformed frontmatter")
        return
    try:
        fm = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError as e:
        r.errors.append(f"workflow.md: invalid YAML: {e}")
        return
    for k in ("name", "description"):
        if k not in fm:
            r.errors.append(f"workflow.md: frontmatter missing `{k}`")


def _check_manifest(path: Path, r: Result) -> None:
    try:
        m = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        r.errors.append(f"manifest.json: invalid JSON: {e}")
        return

    if "contract_version" not in m:
        r.errors.append("manifest.json: missing `contract_version`")

    graph = m.get("graph") or {}
    steps = graph.get("steps") or []
    if not isinstance(steps, list) or not steps:
        r.errors.append("manifest.graph.steps: must be a non-empty list")
        step_ids: list[str] = []
    else:
        step_ids = []
        for i, s in enumerate(steps):
            if not isinstance(s, dict):
                r.errors.append(f"manifest.graph.steps[{i}]: must be a mapping")
                continue
            sid = s.get("id")
            if not sid:
                r.errors.append(f"manifest.graph.steps[{i}]: missing `id`")
                continue
            if sid in step_ids:
                r.errors.append(f"manifest.graph.steps[{i}]: duplicate id `{sid}`")
            step_ids.append(sid)

    trs = graph.get("transitions") or []
    tids: list[Any] = []
    for j, t in enumerate(trs):
        if not isinstance(t, dict):
            r.errors.append(f"manifest.graph.transitions[{j}]: must be a mapping")
            continue
        for k in ("id", "from", "to"):
            if k not in t:
                r.errors.append(f"manifest.graph.transitions[{j}]: missing `{k}`")
        if t.get("from") and t["from"] not in step_ids:
            r.errors.append(f"manifest.graph.transitions[{j}]: from `{t['from']}` not in steps")
        if t.get("to") and t["to"] not in step_ids:
            r.errors.append(f"manifest.graph.transitions[{j}]: to `{t['to']}` not in steps")
        tids.append(t.get("id"))

    for k, b in enumerate(m.get("dynamic_branches") or []):
        if b.get("step") not in step_ids:
            r.errors.append(f"manifest.dynamic_branches[{k}]: step `{b.get('step')}` not in steps")
        for tid in (b.get("transitions") or []):
            if tid not in tids:
                r.errors.append(f"manifest.dynamic_branches[{k}]: transition `{tid}` not in transitions")
