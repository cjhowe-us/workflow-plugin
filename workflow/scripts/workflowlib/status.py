"""Dashboard + progress journal."""

from __future__ import annotations

import datetime
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import paths


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def record(event: dict[str, Any]) -> None:
    """Append an event to the progress journal. Never raises on IO error."""
    try:
        p = paths.progress_journal()
        payload = {"at": _now(), **event}
        with p.open("a") as f:
            f.write(json.dumps(payload) + "\n")
    except OSError:
        pass


def recent(limit: int = 20) -> list[dict[str, Any]]:
    p = paths.progress_journal()
    if not p.is_file():
        return []
    lines = p.read_text().splitlines()
    out: list[dict[str, Any]] = []
    for line in lines[-limit:]:
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def render() -> str:
    """Render a short status line for UserPromptSubmit."""
    events = recent(5)
    if not events:
        return ""
    last = events[-1]
    kind = last.get("event", "?")
    target = last.get("target", "")
    return f"workflow: last {kind} {target}".strip()
