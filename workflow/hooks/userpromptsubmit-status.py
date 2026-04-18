#!/usr/bin/env python3
"""UserPromptSubmit — inject a compact status line."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from workflowlib import lock, paths
from artifactlib import registry


def _gh_user() -> str:
    try:
        out = subprocess.run(
            ["gh", "api", "user", "--jq", ".login"],
            capture_output=True, text=True, timeout=3,
        )
        if out.returncode == 0:
            return out.stdout.strip() or "unknown"
    except (OSError, subprocess.SubprocessError):
        pass
    return "unknown"


def main() -> int:
    state = lock.status()
    gh_user = _gh_user()
    if isinstance(state, dict):
        parts = [f"[workflow] session={state.get('session', '?')} user={gh_user}"]
    else:
        parts = [f"[workflow] {state}"]

    try:
        reg = registry.load_registry()
        entries = reg.get("entries", [])
        counts = {
            "workflows": sum(1 for e in entries if e.get("entry_type") == "workflow"),
            "templates": sum(1 for e in entries if e.get("entry_type") == "artifact-template"),
            "schemes": sum(1 for e in entries if e.get("entry_type") == "artifact-scheme"),
        }
        parts.append(
            f"{counts['workflows']} workflows, {counts['templates']} templates, {counts['schemes']} schemes"
        )
    except registry.RegistryMissing:
        pass

    print(" · ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
