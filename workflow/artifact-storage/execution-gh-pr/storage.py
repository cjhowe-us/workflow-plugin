"""execution-gh-pr storage — stores execution artifacts as GitHub PRs.

URI shape: ``execution|execution-gh-pr/<owner>/<repo>/<pr-number>``.
Progress is journaled as PR comments whose body starts with ``<!-- wf:progress ...`` ``->``.
"""

from __future__ import annotations

import datetime
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# `artifactlib` ships with the artifact plugin — find its scripts/ dir.
_HERE = Path(__file__).resolve()
for _ancestor in _HERE.parents:
    _cand = _ancestor.parent / "artifact" / "artifact" / "scripts"
    if (_cand / "artifactlib").is_dir():
        if str(_cand) not in sys.path:
            sys.path.insert(0, str(_cand))
        break
    _cand = _ancestor.parent / "artifact" / "scripts"
    if (_cand / "artifactlib").is_dir():
        if str(_cand) not in sys.path:
            sys.path.insert(0, str(_cand))
        break

from artifactlib import uri as uri_mod


SUMMARY_TAG = "<!-- wf:summary"
LEDGER_TAG = "<!-- wf:ledger"
PROGRESS_PREFIX = "<!-- wf:progress "


class StorageError(RuntimeError):
    pass


@dataclass(frozen=True)
class PRRef:
    owner: str
    repo: str
    number: int

    @property
    def repo_spec(self) -> str:
        return f"{self.owner}/{self.repo}"


def _now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_uri(raw: str) -> PRRef:
    parsed = uri_mod.try_parse(raw)
    if parsed is None:
        raise StorageError(f"bad uri: {raw}")
    if parsed.scheme != "execution":
        raise StorageError(f"bad scheme: {parsed.scheme}")
    if parsed.backend != "execution-gh-pr":
        raise StorageError(f"bad backend: {parsed.backend}")
    parts = parsed.path.split("/")
    if len(parts) < 3:
        raise StorageError(f"bad uri tail: {parsed.path}")
    owner, repo, num = parts[0], parts[1], parts[2]
    try:
        n = int(num)
    except ValueError as e:
        raise StorageError(f"bad pr number: {num}") from e
    return PRRef(owner=owner, repo=repo, number=n)


def _gh(args: list[str], *, text: str | None = None, timeout: int = 20) -> str:
    import subprocess

    try:
        proc = subprocess.run(
            ["gh", *args],
            capture_output=True,
            text=True,
            input=text,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as e:
        raise StorageError(f"gh call failed: {e}") from e
    if proc.returncode != 0:
        raise StorageError(f"gh {args[0]}: {proc.stderr.strip() or proc.stdout.strip()}")
    return proc.stdout


def _gh_pr_view(pr: PRRef, fields: list[str]) -> dict[str, Any]:
    out = _gh([
        "pr", "view", str(pr.number),
        "--repo", pr.repo_spec,
        "--json", ",".join(fields),
    ])
    return json.loads(out)


def cmd_create(*, scheme: Any, adapter: dict[str, Any], input: Any, uri: str | None) -> dict[str, Any]:
    repo = input.repo
    head = input.head
    if not repo:
        raise StorageError("create: repo required")
    if not head:
        raise StorageError("create: head branch required")

    summary_payload = json.dumps({
        "version": 1,
        "workflow": input.workflow,
        "workflow_inputs": input.workflow_inputs,
        "started_at": _now_iso(),
        "status": "running",
    }, separators=(",", ":"))

    body = (
        f"{SUMMARY_TAG} {summary_payload} -->\n\n"
        f"{input.summary or ''}\n\n"
        f'{LEDGER_TAG} {{"steps":[]}} -->\n'
    )

    title = input.title or "workflow execution"
    base = input.base or "main"

    out = _gh([
        "pr", "create",
        "--repo", repo,
        "--title", title,
        "--body", body,
        "--base", base,
        "--head", head,
        "--draft",
    ])
    m = re.search(r"(\d+)\s*$", out.strip())
    if not m:
        raise StorageError(f"could not parse PR number from: {out.strip()}")
    number = int(m.group(1))
    url = out.strip().splitlines()[-1] if out.strip() else ""

    owner = repo.split("/", 1)[0]
    repo_name = repo.split("/", 1)[1] if "/" in repo else repo
    return {
        "uri": f"execution|execution-gh-pr/{owner}/{repo_name}/{number}",
        "created": True,
    }


def cmd_get(*, scheme: Any, adapter: dict[str, Any], input: Any, uri: str | None) -> dict[str, Any]:
    pr = _parse_uri(input.uri)
    data = _gh_pr_view(pr, ["body", "state", "assignees", "title", "url", "isDraft", "mergedAt"])
    merged = bool(data.get("mergedAt"))
    closed = data.get("state") == "CLOSED"
    status = "complete" if merged else "aborted" if closed else "running"
    content = {
        "workflow": "",  # populated from wf:summary comment if we parse it; left empty on this read
        "workflow_inputs": {},
        "title": data.get("title"),
        "body": data.get("body"),
        "status": status,
        "assignees": [a.get("login") for a in data.get("assignees", []) if isinstance(a, dict)],
        "url": data.get("url"),
    }
    return {
        "uri": input.uri,
        "content": content,
        "edges": [],
    }


def cmd_update(*, scheme: Any, adapter: dict[str, Any], input: Any, uri: str | None) -> dict[str, Any]:
    pr = _parse_uri(input.uri)
    existing = _gh([
        "pr", "view", str(pr.number),
        "--repo", pr.repo_spec,
        "--json", "body",
        "--jq", ".body",
    ]).rstrip("\n")
    new_body = existing + "\n\n<!-- wf:update -->\n" + json.dumps(input.patch)
    _gh([
        "pr", "edit", str(pr.number),
        "--repo", pr.repo_spec,
        "--body", new_body,
    ])
    return {"uri": input.uri, "updated": True}


def cmd_list(*, scheme: Any, adapter: dict[str, Any], input: Any, uri: str | None) -> dict[str, Any]:
    filt = input.filter or {}
    repo = filt.get("repo")
    if not repo:
        raise StorageError("list: filter.repo required")
    state = filt.get("state", "open")
    out = _gh([
        "pr", "list",
        "--repo", repo,
        "--state", state,
        "--search", "in:body wf:summary",
        "--json", "number,title,state,assignees,url",
    ])
    rows = json.loads(out) if out.strip() else []
    owner = repo.split("/", 1)[0]
    repo_name = repo.split("/", 1)[1] if "/" in repo else repo
    return {
        "entries": [
            {
                "uri": f"execution|execution-gh-pr/{owner}/{repo_name}/{row['number']}",
                "title": row.get("title"),
                "state": row.get("state"),
                "assignees": [a.get("login") for a in row.get("assignees", []) if isinstance(a, dict)],
                "url": row.get("url"),
            }
            for row in rows
        ],
    }


def cmd_lock(*, scheme: Any, adapter: dict[str, Any], input: Any, uri: str | None) -> dict[str, Any]:
    pr = _parse_uri(input.uri)
    data = _gh_pr_view(pr, ["assignees"])
    assignees = data.get("assignees", [])
    current = assignees[0].get("login") if assignees and isinstance(assignees[0], dict) else None

    if current and current != input.owner:
        return {"held": False, "current_owner": current}

    _gh([
        "pr", "edit", str(pr.number),
        "--repo", pr.repo_spec,
        "--add-assignee", input.owner,
    ])
    return {"held": True, "current_owner": input.owner}


def cmd_release(*, scheme: Any, adapter: dict[str, Any], input: Any, uri: str | None) -> dict[str, Any]:
    pr = _parse_uri(input.uri)
    data = _gh_pr_view(pr, ["assignees"])
    assignees = data.get("assignees", [])
    current = assignees[0].get("login") if assignees and isinstance(assignees[0], dict) else None
    if current == input.owner:
        try:
            _gh([
                "pr", "edit", str(pr.number),
                "--repo", pr.repo_spec,
                "--remove-assignee", input.owner,
            ])
        except StorageError:
            pass
    return {"released": True}


_STATUS_MAP = {
    ("merged", True): "complete",
    ("closed", False): "aborted",
}


def cmd_status(*, scheme: Any, adapter: dict[str, Any], input: Any, uri: str | None) -> dict[str, Any]:
    pr = _parse_uri(input.uri)
    data = _gh_pr_view(pr, ["state", "isDraft", "closedAt", "mergedAt"])
    merged = bool(data.get("mergedAt"))
    closed = data.get("state") == "CLOSED"
    if merged:
        status = "complete"
    elif closed:
        status = "aborted"
    else:
        status = "running"
    return {"uri": input.uri, "status": status}


_PROGRESS_RE = re.compile(r"<!-- wf:progress (?P<p>\{.*?\}) -->", re.DOTALL)


def cmd_progress(*, scheme: Any, adapter: dict[str, Any], input: Any, uri: str | None) -> dict[str, Any]:
    pr = _parse_uri(input.uri)
    if input.append is None:
        out = _gh([
            "pr", "view", str(pr.number),
            "--repo", pr.repo_spec,
            "--json", "comments",
        ])
        data = json.loads(out) if out.strip() else {"comments": []}
        entries: list[dict[str, Any]] = []
        for comment in data.get("comments", []):
            body = comment.get("body") or ""
            if not body.startswith(PROGRESS_PREFIX):
                continue
            m = _PROGRESS_RE.search(body)
            if not m:
                continue
            try:
                entries.append(json.loads(m.group("p")))
            except json.JSONDecodeError:
                continue
        return {"entries": entries, "appended": False}

    entry_json = json.dumps(input.append, separators=(",", ":"))
    summary = input.append.get("summary") or input.append.get("step") or "progress"
    body = f"<!-- wf:progress {entry_json} -->\n{summary}"
    _gh([
        "pr", "comment", str(pr.number),
        "--repo", pr.repo_spec,
        "--body", body,
    ])
    return {"entries": [], "appended": True}
