#!/usr/bin/env python3
"""PreToolUse — enforce workflow-scoped rules from the active execution.

Stub for now; `rules.check` returns pass-through until dispatch wires per-
execution rule sets.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from workflowlib import rules


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        return 0
    payload = json.loads(raw)
    result = rules.check(payload.get("tool_name", ""), payload.get("tool_input", {}) or {})
    if result.message:
        print(result.message, file=sys.stderr)
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
