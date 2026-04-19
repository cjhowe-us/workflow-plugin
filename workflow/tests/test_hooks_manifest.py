"""Validate hooks/hooks.json wires every event to an existing Python script.

Regression guard: an earlier revision shipped `.sh` hooks while the on-disk
files were `.py`, so the harness silently skipped every hook. This test pins
the contract: every command in hooks.json must run `python3` against a
${CLAUDE_PLUGIN_ROOT}/hooks/<name>.py file that exists.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HOOKS_DIR = REPO / "hooks"
HOOKS_JSON = HOOKS_DIR / "hooks.json"

_CMD_RE = re.compile(r"^python3\s+\$\{CLAUDE_PLUGIN_ROOT\}/hooks/(?P<name>[A-Za-z0-9_\-]+\.py)$")


def _iter_commands():
    data = json.loads(HOOKS_JSON.read_text())
    for event, groups in data["hooks"].items():
        for group in groups:
            for hook in group["hooks"]:
                yield event, hook


def test_hooks_json_exists():
    assert HOOKS_JSON.is_file(), HOOKS_JSON


def test_every_hook_is_python_command():
    for event, hook in _iter_commands():
        assert hook["type"] == "command", (event, hook)
        assert _CMD_RE.match(hook["command"]), (
            f"{event}: hook must be `python3 ${{CLAUDE_PLUGIN_ROOT}}/hooks/<file>.py`, "
            f"got {hook['command']!r}"
        )


def test_every_hook_script_exists_and_is_python():
    missing = []
    for event, hook in _iter_commands():
        m = _CMD_RE.match(hook["command"])
        assert m, hook["command"]
        name = m.group("name")
        path = HOOKS_DIR / name
        if not path.is_file():
            missing.append(f"{event} -> {name}")
    assert not missing, f"hooks.json references non-existent scripts: {missing}"


def test_no_shell_hooks_remain():
    """Catch any regression that re-introduces .sh / .ps1 hook commands."""
    raw = HOOKS_JSON.read_text()
    assert ".sh" not in raw, "hooks.json must not reference .sh scripts"
    assert ".ps1" not in raw, "hooks.json must not reference .ps1 scripts"


def test_no_orphan_hook_scripts():
    """Every .py in hooks/ should be wired into hooks.json (no dead files)."""
    referenced = set()
    for _event, hook in _iter_commands():
        m = _CMD_RE.match(hook["command"])
        assert m
        referenced.add(m.group("name"))

    on_disk = {p.name for p in HOOKS_DIR.glob("*.py")}
    orphans = on_disk - referenced
    assert not orphans, f"hook scripts not referenced by hooks.json: {sorted(orphans)}"
