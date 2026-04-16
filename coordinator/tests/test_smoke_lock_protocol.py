"""Smoke tests for the lock-protocol shell scripts (PR body-marker model).

The `fake_gh` fixture shims a `gh` binary on PATH that stores PRs in an
in-memory map. We run the real shell scripts against it and assert that
acquire/release/heartbeat correctly splice the coordinator HTML-comment
marker into and out of the PR body. Offline; no network, no API key.
"""
from __future__ import annotations

import datetime as dt
import json
import re
import subprocess

import pytest

from conftest import SCRIPTS_DIR, read_pr, seed_pr, seed_repo

REPO = "cjhowe-us/test-sandbox"
PR   = 42
MARKER_RE = re.compile(r'^<!-- coordinator = (\{.*\}) -->$', re.MULTILINE)


def _iso_offset(minutes: int) -> str:
    return (dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=minutes)) \
        .strftime("%Y-%m-%dT%H:%M:%SZ")


def _run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def _sh(name):
    return str(SCRIPTS_DIR / f"{name}.sh")


def _extract_marker(body):
    m = MARKER_RE.search(body or "")
    if not m:
        return None
    return json.loads(m.group(1))


# ---------------------------------------------------------------------------
# acquire
# ---------------------------------------------------------------------------

def test_acquire_writes_marker_into_empty_body(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    seed_pr(state, REPO, PR, body="")

    expiry = _iso_offset(15)
    cp = _run([
        _sh("lock-acquire"),
        "--repo", REPO, "--pr", str(PR),
        "--owner", "host1:sess1:w1", "--expires-at", expiry,
    ])
    assert cp.returncode == 0, cp.stderr

    body = read_pr(state, REPO, PR)["body"]
    marker = _extract_marker(body)
    assert marker is not None
    assert marker["lock_owner"] == "host1:sess1:w1"
    assert marker["lock_expires_at"] == expiry
    assert marker["blocked_by"] == []


def test_acquire_preserves_user_body_above_marker(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    seed_pr(state, REPO, PR, body="## Spec\n\nSome user-authored content.\n")

    expiry = _iso_offset(15)
    cp = _run([
        _sh("lock-acquire"),
        "--repo", REPO, "--pr", str(PR),
        "--owner", "host1:sess1:w1", "--expires-at", expiry,
    ])
    assert cp.returncode == 0, cp.stderr

    body = read_pr(state, REPO, PR)["body"]
    assert body.startswith("## Spec\n\nSome user-authored content.")
    assert _extract_marker(body)["lock_owner"] == "host1:sess1:w1"


def test_second_acquire_on_held_lock_races(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    future = _iso_offset(15)
    body = f'<!-- coordinator = {{"lock_owner":"host1:sess1:w1","lock_expires_at":"{future}","blocked_by":[]}} -->'
    seed_pr(state, REPO, PR, body=body)

    cp = _run([
        _sh("lock-acquire"),
        "--repo", REPO, "--pr", str(PR),
        "--owner", "host2:sess2:w2", "--expires-at", _iso_offset(15),
    ])
    assert cp.returncode == 1, f"expected race exit 1, got {cp.returncode}\n{cp.stderr}"
    assert "raced" in cp.stderr

    after = _extract_marker(read_pr(state, REPO, PR)["body"])
    assert after["lock_owner"] == "host1:sess1:w1"


def test_expired_lock_is_reclaimable(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    past = _iso_offset(-15)
    body = f'existing content\n\n<!-- coordinator = {{"lock_owner":"host1:sess1:w1","lock_expires_at":"{past}","blocked_by":[7]}} -->'
    seed_pr(state, REPO, PR, body=body)

    new_expires = _iso_offset(15)
    cp = _run([
        _sh("lock-acquire"),
        "--repo", REPO, "--pr", str(PR),
        "--owner", "host2:sess2:w2", "--expires-at", new_expires,
    ])
    assert cp.returncode == 0, cp.stderr

    marker = _extract_marker(read_pr(state, REPO, PR)["body"])
    assert marker["lock_owner"] == "host2:sess2:w2"
    assert marker["lock_expires_at"] == new_expires
    # blocked_by is preserved across owner transition.
    assert marker["blocked_by"] == [7]


# ---------------------------------------------------------------------------
# heartbeat
# ---------------------------------------------------------------------------

def test_heartbeat_extends_expiry_without_touching_owner_or_blocked_by(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    expires = _iso_offset(5)
    body = f'<!-- coordinator = {{"lock_owner":"host1:sess1:w1","lock_expires_at":"{expires}","blocked_by":[11,12]}} -->'
    seed_pr(state, REPO, PR, body=body)

    new_expires = _iso_offset(30)
    cp = _run([
        _sh("lock-heartbeat"),
        "--repo", REPO, "--pr", str(PR),
        "--expected-owner", "host1:sess1:w1", "--expires-at", new_expires,
    ])
    assert cp.returncode == 0, cp.stderr

    marker = _extract_marker(read_pr(state, REPO, PR)["body"])
    assert marker["lock_owner"] == "host1:sess1:w1"
    assert marker["lock_expires_at"] == new_expires
    assert marker["blocked_by"] == [11, 12]


def test_heartbeat_on_stolen_lock_fails(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    body = f'<!-- coordinator = {{"lock_owner":"host2:sess2:w2","lock_expires_at":"{_iso_offset(30)}","blocked_by":[]}} -->'
    seed_pr(state, REPO, PR, body=body)

    cp = _run([
        _sh("lock-heartbeat"),
        "--repo", REPO, "--pr", str(PR),
        "--expected-owner", "host1:sess1:w1", "--expires-at", _iso_offset(30),
    ])
    assert cp.returncode == 1
    assert "stolen" in cp.stderr


# ---------------------------------------------------------------------------
# release
# ---------------------------------------------------------------------------

def test_release_strips_marker(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    body = f'Body\n\n<!-- coordinator = {{"lock_owner":"host1:sess1:w1","lock_expires_at":"{_iso_offset(15)}","blocked_by":[]}} -->'
    seed_pr(state, REPO, PR, body=body)

    cp = _run([_sh("lock-release"), "--repo", REPO, "--pr", str(PR)])
    assert cp.returncode == 0, cp.stderr

    after = read_pr(state, REPO, PR)["body"]
    assert "<!-- coordinator" not in after
    assert after.rstrip() == "Body"


def test_release_without_marker_is_noop(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    seed_pr(state, REPO, PR, body="no marker here")

    cp = _run([_sh("lock-release"), "--repo", REPO, "--pr", str(PR)])
    assert cp.returncode == 0
    out = json.loads(cp.stdout.strip())
    assert out["released"] is False
    assert out["reason"] == "no-marker"


def test_release_with_expected_owner_skips_on_mismatch(fake_gh):
    _, state = fake_gh
    seed_repo(state, REPO)
    body = f'<!-- coordinator = {{"lock_owner":"host2:sess2:w2","lock_expires_at":"{_iso_offset(15)}","blocked_by":[]}} -->'
    seed_pr(state, REPO, PR, body=body)

    cp = _run([
        _sh("lock-release"),
        "--repo", REPO, "--pr", str(PR),
        "--expected-owner", "host1:sess1:w1",
    ])
    assert cp.returncode == 0
    out = json.loads(cp.stdout.strip())
    assert out["released"] is False
    assert out["reason"] == "owner-mismatch"
    # Marker untouched.
    assert _extract_marker(read_pr(state, REPO, PR)["body"])["lock_owner"] == "host2:sess2:w2"
