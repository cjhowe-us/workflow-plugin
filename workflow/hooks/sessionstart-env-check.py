#!/usr/bin/env python3
"""SessionStart — verify gh/git/env prerequisites."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from workflowlib import env

if __name__ == "__main__":
    sys.exit(env.main())
