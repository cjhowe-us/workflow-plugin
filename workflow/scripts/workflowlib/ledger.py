"""Per-session dispatch ledger stored at $ARTIFACT_STATE_DIR/workflow/dispatch.json.

Tracks which execution the orchestrator is running, which workers are assigned
to which worktrees, and which steps have cleared.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from . import paths


def file() -> Path:
    return paths.state_dir() / "dispatch.json"


def read() -> dict[str, Any]:
    p = file()
    if not p.is_file():
        return {}
    try:
        return json.loads(p.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def write(data: dict[str, Any]) -> None:
    p = file()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2))


def current_execution() -> str | None:
    return read().get("current_execution") or None


def release_worker(teammate_id: str) -> None:
    data = read()
    workers = data.setdefault("workers", {})
    worktrees = data.setdefault("worktrees", {})
    workers[teammate_id] = None
    data["worktrees"] = {k: v for k, v in worktrees.items() if v.get("worker_id") != teammate_id}
    write(data)
