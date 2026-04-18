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
    # Look for a sibling `artifact` plugin: `<parent-of-workflow-repo>/artifact/artifact/scripts/`.
    for ancestor in here.parents:
        for cand in (
            ancestor.parent / "artifact" / "artifact" / "scripts",
            ancestor.parent / "artifact" / "scripts",
        ):
            if (cand / "artifactlib").is_dir():
                sys.path.insert(0, str(cand))
                return


_bootstrap_artifactlib()
