"""Rule-engine tests — covers the CLAUDE_PLUGIN_DIRS-empty regression."""

from __future__ import annotations

from workflowlib import rules


def test_no_plugin_roots_allows_any_write(monkeypatch):
    monkeypatch.delenv("CLAUDE_PLUGIN_DIRS", raising=False)
    r = rules.no_self_edit("Write", {"file_path": "/tmp/any.txt"})
    assert r.exit_code == 0


def test_write_under_plugin_root_blocks(tmp_path, monkeypatch):
    container = tmp_path / "plugins"
    plugin = container / "someplugin"
    plugin.mkdir(parents=True)
    monkeypatch.setenv("CLAUDE_PLUGIN_DIRS", str(container))

    target = plugin / "file.txt"
    r = rules.no_self_edit("Write", {"file_path": str(target)})
    assert r.exit_code == 2
    assert "plugin root" in r.message


def test_write_outside_plugin_root_passes(tmp_path, monkeypatch):
    container = tmp_path / "plugins"
    (container / "someplugin").mkdir(parents=True)
    monkeypatch.setenv("CLAUDE_PLUGIN_DIRS", str(container))

    r = rules.no_self_edit("Write", {"file_path": "/tmp/not-a-plugin.txt"})
    assert r.exit_code == 0
