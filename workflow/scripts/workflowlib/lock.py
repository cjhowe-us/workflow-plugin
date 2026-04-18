"""Per-machine orchestrator flock.

Uses `fcntl.flock` (POSIX) to guarantee at most one orchestrator per machine
within a single process tree. Cross-session holdover detection falls back to
a json payload with the holder's pid.
"""

from __future__ import annotations

import datetime
import fcntl
import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from . import paths


@dataclass
class Holder:
    pid: int
    session: str
    started_at: str


class LockBusy(RuntimeError):
    pass


def _read_payload(p: Path) -> dict[str, Any] | None:
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def acquire_orchestrator(session: str) -> Holder:
    """Take the orchestrator lock. Raises `LockBusy` if held by a live other session."""
    lock_path = paths.orchestrator_lock_file()
    guard_path = lock_path.with_suffix(".flock")

    existing = _read_payload(lock_path)
    if existing:
        pid = int(existing.get("pid", 0))
        if pid and _pid_alive(pid) and existing.get("session") != session:
            raise LockBusy(f"held by pid={pid} session={existing.get('session')}")

    # Take a best-effort flock on a guard file. Non-blocking; raise if busy.
    guard_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(guard_path), os.O_CREAT | os.O_RDWR, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as e:
        os.close(fd)
        raise LockBusy("orchestrator flock busy (same process tree)") from e

    holder = Holder(
        pid=os.getpid(),
        session=session,
        started_at=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    )
    lock_path.write_text(json.dumps(asdict(holder)))
    # fd stays open for the process lifetime; flock releases automatically on exit.
    return holder


def status() -> dict[str, Any] | str:
    payload = _read_payload(paths.orchestrator_lock_file())
    if payload is None:
        return "free"
    pid = int(payload.get("pid", 0))
    return payload if _pid_alive(pid) else "free (stale)"


def release(session: str | None = None) -> None:
    lock_path = paths.orchestrator_lock_file()
    payload = _read_payload(lock_path)
    if payload is None:
        return
    if session is None or payload.get("session") == session:
        try:
            lock_path.unlink()
        except FileNotFoundError:
            pass
