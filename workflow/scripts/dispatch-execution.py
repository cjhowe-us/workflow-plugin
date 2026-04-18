#!/usr/bin/env python3
"""Shared helper used by workflow-shape artifact templates.

Reads JSON inputs on stdin, resolves the workflow name from the template's
`manifest.json`, and invokes `artifactlib.provider.dispatch("execution",
"create", ...)` with the composed payload. Emits the provider's response on
stdout.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(Path("/Users/cjhowe/Code/artifact/artifact/scripts")))

from artifactlib import provider


def _gh_user() -> str | None:
    try:
        out = subprocess.run(
            ["gh", "api", "user", "--jq", ".login"],
            capture_output=True, text=True, timeout=3,
        )
        if out.returncode == 0:
            return out.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("template_dir", help="Path to the template directory containing manifest.json")
    args = parser.parse_args(argv)

    template_dir = Path(args.template_dir)
    manifest_path = template_dir / "manifest.json"
    if not manifest_path.is_file():
        print(json.dumps({"error": "missing manifest.json"}), file=sys.stdout)
        return 2

    inputs_raw = sys.stdin.read().strip()
    inputs: dict[str, Any] = json.loads(inputs_raw) if inputs_raw else {}
    manifest = json.loads(manifest_path.read_text())
    wf_name = manifest.get("name")
    if not wf_name:
        print(json.dumps({"error": "manifest missing name"}), file=sys.stdout)
        return 2

    owner = inputs.get("owner") or _gh_user()
    parent = inputs.get("parent_execution")

    payload = {
        "workflow": wf_name,
        "workflow_inputs": inputs,
        "owner": owner,
        "parent_execution": parent,
    }

    try:
        out = provider.dispatch(
            scheme_name="execution",
            subcommand="create",
            payload=payload,
            uri_str=None,
            storage_override=None,
        )
    except Exception as e:  # noqa: BLE001 — mediator may raise several types; JSON error is the contract
        print(json.dumps({"error": str(e)}))
        return 2

    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
