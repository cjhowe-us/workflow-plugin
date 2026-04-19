"""PreToolUse rule engine.

Replaces `pretooluse-no-self-edit.sh` (with bug fix) and `pretooluse-rules.sh`.
The python impl eliminates the empty-array footgun that made the old bash
hook block every write when `CLAUDE_PLUGIN_DIRS` was unset.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

_BASH_WRITE_PATTERN = re.compile(r"(>>?|\brm\s+-[rf]+\b|\bmv\b|\btee\b|\bcp\b)\s+(\S+)")


@dataclass
class RuleResult:
    exit_code: int
    message: str = ""


def plugin_roots() -> list[Path]:
    """Return directories that count as plugin roots.

    Reads `CLAUDE_PLUGIN_DIRS`, ":"-separated on POSIX / ";" on Windows. Each
    top-level entry is treated as a container; its immediate subdirectories are
    plugin roots. Non-existent paths are silently skipped.
    """
    raw = os.environ.get("CLAUDE_PLUGIN_DIRS", "")
    if not raw:
        return []
    sep = ";" if os.name == "nt" else ":"
    out: list[Path] = []
    for chunk in raw.split(sep):
        root = Path(chunk)
        if not root.is_dir():
            continue
        for child in root.iterdir():
            if child.is_dir():
                out.append(child.resolve())
    return out


def candidate_paths(tool_name: str, tool_input: dict) -> list[Path]:
    """Extract paths a tool is about to write to."""
    paths: list[Path] = []
    if tool_name in {"Edit", "Write"}:
        p = tool_input.get("file_path")
        if p:
            paths.append(Path(p))
    elif tool_name == "Bash":
        cmd = tool_input.get("command", "")
        for m in _BASH_WRITE_PATTERN.finditer(cmd):
            paths.append(Path(m.group(2)))
    return paths


def no_self_edit(tool_name: str, tool_input: dict) -> RuleResult:
    """Block writes under any installed plugin root.

    Previously in bash: when `CLAUDE_PLUGIN_DIRS` was unset, the check matched
    every absolute path. In python the list is simply empty and we bail early.
    """
    roots = plugin_roots()
    if not roots:
        return RuleResult(0)

    for path in candidate_paths(tool_name, tool_input):
        abs_path = path.resolve() if path.exists() else Path(os.path.abspath(str(path)))
        for root in roots:
            try:
                abs_path.relative_to(root)
            except ValueError:
                continue
            return RuleResult(
                2,
                f"workflow: write denied under plugin root {root}\n"
                f"  Plugin files are immutable to agents. Use override scope or open a PR.",
            )
    return RuleResult(0)


def check(tool_name: str, tool_input: dict) -> RuleResult:
    """Execution-scoped rules — placeholder for now; wire up per-execution
    allowlists once `workflowlib.dispatch` records the active execution's scope.
    """
    return RuleResult(0)
