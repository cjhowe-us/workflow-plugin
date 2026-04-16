"""Smoke test for the pr-scan.sh script.

Seed a repo with a mix of PRs — some carrying `phase:*` labels with
various marker states, some unrelated — and assert that pr-scan emits
one record per managed PR with the expected shape (phase extracted,
marker fields parsed, non-managed PRs excluded).
"""
from __future__ import annotations

import json
import subprocess

import pytest

from conftest import SCRIPTS_DIR, seed_pr, seed_repo

REPO = "cjhowe-us/test-sandbox"


def _sh(name):
    return str(SCRIPTS_DIR / f"{name}.sh")


def _run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def test_pr_scan_emits_one_record_per_managed_pr(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)

    # PR #1 — managed, no marker.
    seed_pr(state, REPO, 1,
            headRefName="coordinator/specify-login",
            labels=["phase:specify"],
            body="")

    # PR #2 — managed, marker with owner + deps.
    seed_pr(state, REPO, 2,
            headRefName="coordinator/design-tokens",
            labels=["phase:design", "area:auth"],
            body=('Design prose here.\n\n'
                  '<!-- coordinator = {"lock_owner":"host1:sess1:w1","lock_expires_at":"2099-01-01T00:00:00Z","blocked_by":[1]} -->'))

    # PR #3 — NOT managed (no phase:* label).
    seed_pr(state, REPO, 3,
            headRefName="feature/unrelated",
            labels=["bug"],
            body="")

    cp = _run([_sh("pr-scan"), REPO])
    assert cp.returncode == 0, cp.stderr

    records = [json.loads(line) for line in cp.stdout.strip().splitlines()]
    assert len(records) == 2, f"got {records}"

    by_num = {r["number"]: r for r in records}

    r1 = by_num[1]
    assert r1["repo"] == REPO
    assert r1["phase"] == "specify"
    assert r1["state"] == "open"
    assert r1["is_draft"] is True
    assert r1["head_ref_name"] == "coordinator/specify-login"
    assert r1["lock_owner"] == ""
    assert r1["lock_expires_at"] == ""
    assert r1["blocked_by"] == []

    r2 = by_num[2]
    assert r2["phase"] == "design"
    assert r2["lock_owner"] == "host1:sess1:w1"
    assert r2["lock_expires_at"] == "2099-01-01T00:00:00Z"
    assert r2["blocked_by"] == [1]
