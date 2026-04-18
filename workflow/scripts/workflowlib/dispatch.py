"""Dispatch a workflow into an execution artifact.

The plan describes a two-phase flow:

1. Read the workflow definition (`workflows/<n>/{workflow.md, manifest.json}`).
2. Call `artifactlib.provider.dispatch("execution", "create", payload)` to
   instantiate an execution artifact (storage: `execution-gh-pr`).

For now this is a thin shim that validates inputs and delegates. Richer
orchestration (step graph traversal, transitions, dynamic branches) lives in
`workflowlib.dispatch.run()` — TODO after Step 4 lands the scheme/storage.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from artifactlib import provider


def instantiate(workflow_dir: Path, inputs: dict[str, Any], storage: str | None = None) -> dict[str, Any]:
    if not (workflow_dir / "manifest.json").is_file():
        raise FileNotFoundError(f"workflow manifest missing: {workflow_dir}/manifest.json")
    if not (workflow_dir / "workflow.md").is_file():
        raise FileNotFoundError(f"workflow definition missing: {workflow_dir}/workflow.md")

    manifest = json.loads((workflow_dir / "manifest.json").read_text())
    payload = {
        "workflow": manifest.get("name") or workflow_dir.name,
        "inputs": inputs,
    }
    return provider.dispatch(
        scheme_name="execution",
        subcommand="create",
        payload=payload,
        uri_str=None,
        storage_override=storage,
    )
