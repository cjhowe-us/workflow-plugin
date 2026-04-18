#!/usr/bin/env python3
"""PreToolUse — block writes under installed plugin roots.

Includes the regression fix: when CLAUDE_PLUGIN_DIRS is unset, the previous
bash hook matched every absolute path. In python `rules.plugin_roots()` returns
`[]` and the check short-circuits cleanly.
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
    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {}) or {}
    result = rules.no_self_edit(tool_name, tool_input)
    if result.message:
        print(result.message, file=sys.stderr)
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
