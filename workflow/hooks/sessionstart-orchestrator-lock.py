#!/usr/bin/env python3
"""SessionStart — take the per-machine orchestrator flock.

Fails with exit 2 if another live orchestrator holds it.
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from workflowlib import lock


def main() -> int:
    session = os.environ.get("CLAUDE_SESSION_ID") or f"sess-{int(time.time())}-{os.getpid()}"
    try:
        lock.acquire_orchestrator(session)
    except lock.LockBusy as e:
        print(f"workflow: another orchestrator is running on this machine ({e}).", file=sys.stderr)
        print("Exit that session first, or wait for it to terminate.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
