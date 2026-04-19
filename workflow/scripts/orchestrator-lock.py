#!/usr/bin/env python3
"""Operate on the per-machine orchestrator flock.

orchestrator-lock.py status   # print current holder (or "free")
orchestrator-lock.py release  # clear the lock file (use with caution)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from workflowlib import lock


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("cmd", choices=["status", "release"])
    args = parser.parse_args(argv)

    if args.cmd == "status":
        s = lock.status()
        if isinstance(s, dict):
            print(json.dumps(s))
        else:
            print(s)
        return 0

    lock.release()
    print("released")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
