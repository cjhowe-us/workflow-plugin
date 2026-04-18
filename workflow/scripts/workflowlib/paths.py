"""Resolve workflow-scoped state directories.

Piggybacks `artifactlib.xdg` so workflow state lives beside artifact state. The
orchestrator lock file is per-machine; everything else is XDG-compliant.
"""

from __future__ import annotations

from pathlib import Path

from artifactlib import xdg


def state_dir() -> Path:
    d = xdg.resolve().state / "workflow"
    d.mkdir(parents=True, exist_ok=True)
    return d


def orchestrator_lock_file() -> Path:
    return state_dir() / "orchestrator.lock"


def progress_journal() -> Path:
    return state_dir() / "progress.jsonl"
