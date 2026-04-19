"""Environment check — equivalent of sessionstart-env-check.sh."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass, field


@dataclass
class EnvReport:
    warnings: list[str] = field(default_factory=list)
    fatal: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.fatal


def check() -> EnvReport:
    r = EnvReport()

    if shutil.which("git") is None:
        r.fatal.append("git not found on PATH. Install git to use the workflow plugin.")

    if shutil.which("gh") is None:
        r.warnings.append("gh CLI not found. Install: https://cli.github.com/")
    else:
        proc = subprocess.run(
            ["gh", "auth", "status"],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            r.warnings.append("gh is not authenticated. Run: gh auth login")

    if os.environ.get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS") != "1":
        r.fatal.append(
            "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS must be set to 1. Export it in your shell rc."
        )

    return r


def main() -> int:
    report = check()
    for w in report.warnings:
        print(f"workflow: {w}", file=sys.stderr)
    for f in report.fatal:
        print(f"workflow: {f}", file=sys.stderr)
    return 0 if report.ok else 2
