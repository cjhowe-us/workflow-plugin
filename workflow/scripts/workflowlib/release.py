"""Release hooks — called on SubagentStop."""

from __future__ import annotations

from . import lock, status


def on_subagent_stop(session: str | None = None) -> None:
    lock.release(session)
    status.record({"event": "subagent_stop", "session": session})
