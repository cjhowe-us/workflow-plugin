#!/usr/bin/env python3
"""SubagentStop — scrub worker/worktree entries from the dispatch ledger."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from workflowlib import ledger, release


def main() -> int:
    raw = sys.stdin.read()
    payload = json.loads(raw) if raw.strip() else {}
    teammate = payload.get("teammate_id") or payload.get("agent_id")
    if not teammate:
        return 0
    ledger.release_worker(teammate)
    release.on_subagent_stop(teammate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
