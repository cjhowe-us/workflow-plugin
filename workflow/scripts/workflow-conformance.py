#!/usr/bin/env python3
"""Validate a workflow directory against the workflow contract.

Usage:
    workflow-conformance.py <path-to-workflow-dir-or-workflow.md>
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from workflowlib import conformance


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: workflow-conformance.py <dir-or-workflow.md>", file=sys.stderr)
        return 2

    arg = Path(argv[0])
    if arg.is_dir():
        target = arg
    elif arg.is_file():
        target = arg.parent
    else:
        print(f"not-found: {arg}", file=sys.stderr)
        return 2

    r = conformance.check(target)
    if not r.ok:
        for e in r.errors:
            print(f"workflow-conformance: {e}", file=sys.stderr)
        return 1
    print(f"workflow-conformance: {target} OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
