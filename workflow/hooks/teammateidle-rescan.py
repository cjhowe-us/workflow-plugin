#!/usr/bin/env python3
"""TeammateIdle — drop a rescan flag for the orchestrator's next turn."""

from __future__ import annotations

import datetime
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from workflowlib import paths


def main() -> int:
    flag = paths.state_dir() / "rescan.flag"
    flag.write_text(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
