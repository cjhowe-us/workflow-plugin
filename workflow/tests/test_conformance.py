"""Conformance tests for the four base workflows."""

from __future__ import annotations

from pathlib import Path

from workflowlib import conformance


REPO = Path(__file__).resolve().parent.parent


def test_default_passes():
    r = conformance.check(REPO / "workflows" / "default")
    assert r.ok, r.errors


def test_conductor_passes():
    r = conformance.check(REPO / "workflows" / "conductor")
    assert r.ok, r.errors


def test_plan_do_passes():
    r = conformance.check(REPO / "workflows" / "plan-do")
    assert r.ok, r.errors


def test_write_review_passes():
    r = conformance.check(REPO / "workflows" / "write-review")
    assert r.ok, r.errors


def test_missing_manifest_fails(tmp_path):
    d = tmp_path / "bad"
    d.mkdir()
    (d / "workflow.md").write_text("---\nname: x\ndescription: y\n---\n")
    r = conformance.check(d)
    assert not r.ok


def test_missing_frontmatter_fails(tmp_path):
    d = tmp_path / "bad"
    d.mkdir()
    (d / "workflow.md").write_text("no frontmatter")
    (d / "manifest.json").write_text('{"contract_version":1,"graph":{"steps":[{"id":"a"}]}}')
    r = conformance.check(d)
    assert not r.ok
