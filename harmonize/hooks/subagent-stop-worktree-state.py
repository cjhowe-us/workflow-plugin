#!/usr/bin/env python3
"""On subagentStop: mark task stopped in docs/plans/worktree-state.json (remove from running_tasks)."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def _repo_root() -> Path:
    import os

    start = Path.cwd().resolve()
    for key in ("CURSOR_WORKSPACE_ROOT", "CLAUDE_PROJECT_ROOT", "PWD"):
        v = os.environ.get(key)
        if v:
            start = Path(v).resolve()
            break
    for p in (start, *start.parents):
        if (p / "docs" / "plans").is_dir():
            return p
    return start


def _task_id(payload: dict) -> str | None:
    for k in (
        "taskId",
        "task_id",
        "id",
        "subagentTaskId",
        "subagent_task_id",
    ):
        v = payload.get(k)
        if v is not None and str(v).strip():
            return str(v).strip()
    nested = payload.get("task") or payload.get("subagent") or {}
    if isinstance(nested, dict):
        for k in ("taskId", "task_id", "id"):
            v = nested.get(k)
            if v is not None and str(v).strip():
                return str(v).strip()
    return None


def main() -> int:
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    root = _repo_root()
    path = root / "docs" / "plans" / "worktree-state.json"
    if not path.parent.is_dir():
        return 0

    tid = _task_id(payload)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            data = {}
    else:
        data = {}
    if not isinstance(data, dict):
        data = {}

    tasks = data.get("running_tasks")
    if not isinstance(tasks, list):
        tasks = []

    if tid:
        tasks = [
            t
            for t in tasks
            if not (isinstance(t, dict) and str(t.get("task_id")) == tid)
        ]
        last_stop = {"status": "stopped", "stopped_at": now, "task_id": tid}
    else:
        last_stop = {"status": "stopped", "stopped_at": now, "task_id": None}

    out = {
        "last_subagent_stop": last_stop,
        "running_tasks": tasks,
        "updated_at": now,
        "workspace": str(root),
    }
    path.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
