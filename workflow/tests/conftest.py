"""Shared fixtures for the workflow plugin test suite.

Mirrors the conftest patterns shipped by the artifact + artifact-github plugins.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
WORKFLOW_SCRIPTS = REPO / "scripts"
if str(WORKFLOW_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(WORKFLOW_SCRIPTS))


def _find_artifact_scripts() -> Path | None:
    """Walk up from this repo to locate the sibling artifact plugin's scripts/."""
    for ancestor in REPO.parents:
        cand = ancestor.parent / "artifact" / "artifact" / "scripts"
        if (cand / "artifactlib").is_dir():
            return cand
        cand = ancestor.parent / "artifact" / "scripts"
        if (cand / "artifactlib").is_dir():
            return cand
    return None


_ARTIFACT_SCRIPTS = _find_artifact_scripts()
if _ARTIFACT_SCRIPTS and str(_ARTIFACT_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_ARTIFACT_SCRIPTS))


@pytest.fixture
def tmp_worktree(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Fresh git worktree + isolated XDG dirs; chdir into it."""
    subprocess.run(
        ["git", "init", "-q", str(tmp_path)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("ARTIFACT_CONFIG_DIR", str(tmp_path / ".artifact-config"))
    monkeypatch.setenv("ARTIFACT_CACHE_DIR", str(tmp_path / ".artifact-cache"))
    monkeypatch.setenv("ARTIFACT_STATE_DIR", str(tmp_path / ".artifact-state"))
    return tmp_path
