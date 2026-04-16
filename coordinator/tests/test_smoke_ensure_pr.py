"""Smoke test for the ensure-pr.sh script.

Two modes:

- Existing PR: given `--pr N`, returns metadata without side effects.
- New PR: given `--title` + `--phase`, creates a draft PR and attaches
  the `phase:<name>` label.
"""
from __future__ import annotations

import json
import subprocess

import pytest

from conftest import SCRIPTS_DIR, read_pr, seed_pr, seed_repo

REPO = "cjhowe-us/test-sandbox"


def _sh(name):
    return str(SCRIPTS_DIR / f"{name}.sh")


def _run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def test_ensure_pr_existing_returns_metadata(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    seed_pr(state, REPO, 7,
            headRefName="coordinator/specify-foo",
            labels=["phase:specify"])

    cp = _run([_sh("ensure-pr"), "--repo", REPO, "--pr", "7"])
    assert cp.returncode == 0, cp.stderr

    out = json.loads(cp.stdout.strip())
    assert out == {
        "pr_number": 7,
        "branch": "coordinator/specify-foo",
        "phase": "specify",
        "created_pr": False,
    }


def test_ensure_pr_creates_new_draft_with_phase_label(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)

    cp = _run([
        _sh("ensure-pr"),
        "--repo", REPO,
        "--title", "Add user login spec",
        "--phase", "specify",
        "--branch", "coordinator/specify-login",
    ])
    assert cp.returncode == 0, cp.stderr

    out = json.loads(cp.stdout.strip())
    assert out["created_pr"] is True
    assert out["phase"] == "specify"
    assert out["branch"] == "coordinator/specify-login"

    pr_num = out["pr_number"]
    pr = read_pr(state, REPO, pr_num)
    assert pr["isDraft"] is True
    assert pr["headRefName"] == "coordinator/specify-login"
    assert pr["title"] == "Add user login spec"
    # phase:specify label attached.
    assert any(l["name"] == "phase:specify" for l in pr["labels"])


def test_ensure_pr_invalid_phase_errors(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)

    cp = _run([
        _sh("ensure-pr"),
        "--repo", REPO,
        "--title", "x",
        "--phase", "nonsense",
        "--branch", "coordinator/nope",
    ])
    assert cp.returncode == 2
    assert "invalid --phase" in cp.stderr
