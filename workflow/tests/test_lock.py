"""Lock tests."""

from __future__ import annotations

import os

from workflowlib import lock


def test_acquire_then_release(monkeypatch, tmp_path):
    monkeypatch.setenv("ARTIFACT_STATE_DIR", str(tmp_path / "state"))
    holder = lock.acquire_orchestrator("sess-test-1")
    assert holder.pid == os.getpid()
    assert holder.session == "sess-test-1"
    state = lock.status()
    assert isinstance(state, dict)
    lock.release("sess-test-1")
    assert lock.status() == "free"


def test_status_free_when_no_lock(monkeypatch, tmp_path):
    monkeypatch.setenv("ARTIFACT_STATE_DIR", str(tmp_path / "state"))
    assert lock.status() == "free"
