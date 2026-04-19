"""Teammate-idle handler — trigger a registry rescan."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def rescan() -> None:
    """Call the artifact discover script. Best-effort; failure is non-fatal."""
    discover = _discover_script()
    if discover is None:
        return
    try:
        subprocess.run([sys.executable, str(discover)], check=False, timeout=30)
    except (subprocess.SubprocessError, OSError):
        pass


def _discover_script() -> Path | None:
    """Find artifact/scripts/discover.py. Walk up from this file's location."""
    here = Path(__file__).resolve()
    for ancestor in here.parents:
        # Plugin layout: <parent>/artifact/scripts/discover.py.
        candidate = ancestor.parent / "artifact" / "scripts" / "discover.py"
        if candidate.is_file():
            return candidate
        if ancestor.name == "Code":
            candidate = ancestor / "artifact" / "artifact" / "scripts" / "discover.py"
            if candidate.is_file():
                return candidate
    return None
