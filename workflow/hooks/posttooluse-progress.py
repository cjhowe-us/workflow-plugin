#!/usr/bin/env python3
"""PostToolUse — append a progress entry to the active execution."""

from __future__ import annotations

import datetime
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from workflowlib import ledger, status


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _summarize(tool_name: str, tool_input: dict) -> str | None:
    if tool_name in {"Edit", "Write"}:
        p = tool_input.get("file_path", "")
        return f"{tool_name} {p}"
    if tool_name == "Bash":
        cmd = tool_input.get("command", "")[:120]
        return f"Bash: {cmd}"
    return tool_name or None


def main() -> int:
    exec_uri = ledger.current_execution()
    raw = sys.stdin.read()
    payload = json.loads(raw) if raw.strip() else {}

    summary = _summarize(payload.get("tool_name", ""), payload.get("tool_input", {}) or {})
    if not summary:
        return 0

    status.record({"event": "tool_use", "tool": payload.get("tool_name"), "summary": summary})

    if not exec_uri:
        return 0

    scheme = exec_uri.split(":", 1)[0]
    entry = json.dumps(
        {
            "at": _now(),
            "kind": "tool_use",
            "summary": summary,
            "tool": payload.get("tool_name"),
            "auto_generated": True,
        }
    )

    run_provider = Path(__file__).resolve().parent.parent / "scripts" / "run-provider.py"
    artifact_run_provider = Path("/Users/cjhowe/Code/artifact/artifact/scripts/run-provider.py")
    script = run_provider if run_provider.is_file() else artifact_run_provider

    try:
        subprocess.run(
            [sys.executable, str(script), scheme, "progress", "--uri", exec_uri, "--append", "-"],
            input=entry,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
