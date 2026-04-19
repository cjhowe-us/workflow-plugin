"""Workflow plugin runtime library.

Dev-mode bootstrap: if `artifactlib` isn't importable (no pip install),
walk up from this file to find a sibling `artifact/scripts/` checkout and
insert it on `sys.path`. In production the `artifact` package is installed
via `pyproject.toml` and this path-munging is a no-op.
"""

from __future__ import annotations

import sys
from pathlib import Path


def _bootstrap_artifactlib() -> None:
    try:
        import artifactlib  # noqa: F401

        return
    except ImportError:
        pass

    here = Path(__file__).resolve()
    # Layouts we want to cover:
    #   dev checkout:   <sibling>/artifact/artifact/scripts/artifactlib
    #   legacy mono:    <sibling>/artifact/scripts/artifactlib
    #   plugin cache:   <sibling>/artifact/<version>/scripts/artifactlib
    for ancestor in here.parents:
        artifact_root = ancestor.parent / "artifact"
        if not artifact_root.is_dir():
            continue
        candidates = [
            artifact_root / "artifact" / "scripts",
            artifact_root / "scripts",
        ]
        candidates.extend(sorted(artifact_root.glob("*/scripts"), reverse=True))
        for cand in candidates:
            if (cand / "artifactlib").is_dir():
                sys.path.insert(0, str(cand))
                return


_bootstrap_artifactlib()
