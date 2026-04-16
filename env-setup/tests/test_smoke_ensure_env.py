"""Smoke tests for ensure-env.sh (POSIX path).

Runs the real script with $SHELL and $HOME pointed at a temp dir so the
test never mutates the real user's profile. Covers:

- Creates the config file with the right export line.
- Idempotent: second run is a no-op.
- --dry-run prints target + line and writes nothing.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

ENSURE_ENV = Path(__file__).resolve().parents[1] / "skills" / "env-setup" / "scripts" / "ensure-env.sh"


def _env_for(shell_abspath: str, home: Path) -> dict:
    env = os.environ.copy()
    env["SHELL"] = shell_abspath
    env["HOME"] = str(home)
    return env


def _run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_ensure_env_zsh_writes_export(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    env = _env_for("/bin/zsh", home)

    cp = _run(
        [str(ENSURE_ENV), "--var", "FOO", "--value", "bar"],
        env=env,
    )
    assert cp.returncode == 0, cp.stderr

    zshrc = home / ".zshrc"
    assert zshrc.exists()
    assert "export FOO=bar" in zshrc.read_text()


def test_ensure_env_zsh_is_idempotent(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    env = _env_for("/bin/zsh", home)

    _run([str(ENSURE_ENV), "--var", "FOO", "--value", "bar"], env=env)
    content_after_first = (home / ".zshrc").read_text()

    cp = _run([str(ENSURE_ENV), "--var", "FOO", "--value", "bar"], env=env)
    assert cp.returncode == 0
    assert "already set" in cp.stdout.lower()
    assert (home / ".zshrc").read_text() == content_after_first


def test_ensure_env_dry_run_writes_nothing(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    env = _env_for("/bin/zsh", home)

    cp = _run(
        [str(ENSURE_ENV), "--var", "FOO", "--value", "bar", "--dry-run"],
        env=env,
    )
    assert cp.returncode == 0
    assert "would append" in cp.stdout.lower()
    assert "export FOO=bar" in cp.stdout
    assert not (home / ".zshrc").exists()


def test_ensure_env_fish_uses_set_gx(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    env = _env_for("/usr/bin/fish", home)

    cp = _run(
        [str(ENSURE_ENV), "--var", "FOO", "--value", "bar"],
        env=env,
    )
    assert cp.returncode == 0, cp.stderr

    cfg = home / ".config" / "fish" / "config.fish"
    assert cfg.exists()
    assert "set -gx FOO bar" in cfg.read_text()


def test_ensure_env_with_comment(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    env = _env_for("/bin/zsh", home)

    cp = _run(
        [str(ENSURE_ENV), "--var", "FOO", "--value", "bar",
         "--comment", "for the acme plugin"],
        env=env,
    )
    assert cp.returncode == 0, cp.stderr

    body = (home / ".zshrc").read_text()
    assert "# for the acme plugin" in body
    assert "export FOO=bar" in body
