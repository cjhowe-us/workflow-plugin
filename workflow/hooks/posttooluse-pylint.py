#!/usr/bin/env python3
"""PostToolUse — run ruff + mypy against any .py file the agent just edited.

Surfaces lint/type regressions in-flight so the agent fixes them before
moving on, rather than discovering them in CI. Best-effort: missing
toolchains return 0 silently — CI is the source of truth.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


def _edited_path(payload: dict[str, object]) -> Path | None:
    tool = payload.get("tool_name")
    raw = payload.get("tool_input")
    if not isinstance(raw, dict):
        return None
    if tool not in {"Edit", "Write"}:
        return None
    p = raw.get("file_path")  # ty: ignore[invalid-argument-type]
    if not isinstance(p, str) or not p.endswith(".py"):
        return None
    path = Path(p)
    return path if path.is_file() else None


def _run(cmd: list[str], target: Path) -> tuple[int, str]:
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError) as e:
        return 0, f"  (skipped, exec failed: {e})"
    out = (proc.stdout + proc.stderr).strip()
    return proc.returncode, out


def _emit(label: str, code: int, out: str, target: Path) -> None:
    if code == 0 and not out:
        return
    print(f"[posttooluse-pylint] {label} on {target}:", file=sys.stderr)
    if out:
        print(out, file=sys.stderr)


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        return 0
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return 0
    target = _edited_path(payload)
    if target is None:
        return 0

    # ruff: lint + format check
    if shutil.which("ruff") or shutil.which("uvx"):
        ruff_cmd = (
            ["ruff", "check", str(target)]
            if shutil.which("ruff")
            else ["uvx", "ruff", "check", str(target)]
        )
        code, out = _run(ruff_cmd, target)
        _emit("ruff check", code, out, target)

    # mypy: only meaningful for files inside the plugin tree (project config)
    plugin_root = Path(__file__).resolve().parent.parent
    try:
        target.resolve().relative_to(plugin_root)
    except ValueError:
        return 0
    mypy_bin = shutil.which("mypy")
    if mypy_bin:
        code, out = _run([mypy_bin, str(target)], target)
        _emit("mypy", code, out, target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
