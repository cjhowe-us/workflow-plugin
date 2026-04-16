"""Fixtures for the coordinator test suite.

`fake_gh` — writes a Python shim on PATH that mimics the subset of the
`gh` CLI the plugin actually uses (pr view/edit/create/list, label create,
repo view) against an in-memory repo map. Offline; no network, no API key.
"""
from __future__ import annotations

import json
import os
import stat
import subprocess
import textwrap
from pathlib import Path

import pytest

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = PLUGIN_ROOT / "scripts"


@pytest.fixture
def fake_gh(tmp_path, monkeypatch):
    """Install a fake `gh` binary backed by a JSON state file.

    State schema:
      {
        "repos": {
          "owner/name": {
            "default_branch": "main",
            "next_pr_number": 1,
            "labels": ["phase:specify", ...],
            "prs": {
              "<N>": {
                "number": N,
                "state": "OPEN" | "CLOSED" | "MERGED",
                "isDraft": true | false,
                "headRefName": "...",
                "title": "...",
                "body": "...",
                "labels": [{"name": "phase:..."}]
              }
            }
          }
        }
      }

    Yields `(bin_dir, state_path)`. Tests call `seed_repo` / `seed_pr` /
    `read_pr` to drive.
    """
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()

    state_path = tmp_path / "gh-state.json"
    state_path.write_text(json.dumps({"repos": {}}))

    fake_gh_py = bin_dir / "gh"
    fake_gh_py.write_text(textwrap.dedent(f"""
        #!/usr/bin/env python3
        import json, os, sys
        STATE = {json.dumps(str(state_path))!s}

        def load(): return json.loads(open(STATE).read())
        def save(s): open(STATE, "w").write(json.dumps(s, indent=2))

        def flag(name):
            if name in sys.argv:
                i = sys.argv.index(name)
                if i + 1 < len(sys.argv):
                    return sys.argv[i + 1]
            return None

        def get_repo(state, name):
            return state["repos"].setdefault(name, {{
                "default_branch": "main",
                "next_pr_number": 1,
                "labels": [],
                "prs": {{}},
            }})

        def repo_from_flag(state):
            r = flag("--repo")
            if not r:
                sys.stderr.write("fake gh: --repo required\\n"); sys.exit(2)
            return r, get_repo(state, r)

        def json_fields(raw, pr):
            fields = raw.split(",") if raw else []
            out = {{}}
            for f in fields:
                if f == "labels":
                    out[f] = pr.get("labels", [])
                elif f == "body":
                    out[f] = pr.get("body", "")
                else:
                    out[f] = pr.get(f)
            return out

        def apply_jq_q(obj, q):
            if not q or q == ".":
                return obj
            # Minimal jq support: ".field" and ".field.field"
            cur = obj
            for part in q.lstrip(".").split("."):
                if part == "":
                    continue
                if isinstance(cur, dict):
                    cur = cur.get(part)
                else:
                    return None
            return cur

        args = sys.argv[1:]
        state = load()

        # --- gh repo view -------------------------------------------------
        if args[:2] == ["repo", "view"] and len(args) >= 3 and not args[2].startswith("-"):
            # args[2] is "owner/name"
            r = args[2]
            info = get_repo(state, r)
            save(state)
            raw = flag("--json") or ""
            q = flag("-q") or ""
            if "defaultBranchRef" in raw:
                payload = {{"defaultBranchRef": {{"name": info["default_branch"]}}}}
            else:
                payload = {{}}
            if q:
                v = apply_jq_q(payload, q)
                print(v if v is not None else "")
            else:
                print(json.dumps(payload))
            sys.exit(0)

        # --- gh pr view ---------------------------------------------------
        if args[:2] == ["pr", "view"] and len(args) >= 3:
            num = int(args[2])
            repo_name, repo = repo_from_flag(state)
            pr = repo["prs"].get(str(num))
            if not pr:
                sys.stderr.write(f"fake gh: no PR #{{num}} in {{repo_name}}\\n"); sys.exit(1)
            raw = flag("--json")
            q = flag("-q") or ""
            payload = json_fields(raw, pr)
            if q:
                v = apply_jq_q(payload, q)
                if v is None:
                    print("")
                elif isinstance(v, (dict, list)):
                    print(json.dumps(v))
                else:
                    print(v)
            else:
                print(json.dumps(payload))
            sys.exit(0)

        # --- gh pr list ---------------------------------------------------
        if args[:2] == ["pr", "list"]:
            repo_name, repo = repo_from_flag(state)
            raw = flag("--json") or ""
            fields = raw.split(",") if raw else []
            want_state = flag("--state") or "open"
            out = []
            for pr in repo["prs"].values():
                if want_state != "all" and pr.get("state", "").lower() != want_state.lower():
                    continue
                row = {{}}
                for f in fields:
                    if f == "labels":
                        row[f] = pr.get("labels", [])
                    elif f == "body":
                        row[f] = pr.get("body", "")
                    else:
                        row[f] = pr.get(f)
                out.append(row)
            print(json.dumps(out))
            sys.exit(0)

        # --- gh pr edit ---------------------------------------------------
        if args[:2] == ["pr", "edit"] and len(args) >= 3:
            num = int(args[2])
            repo_name, repo = repo_from_flag(state)
            pr = repo["prs"].get(str(num))
            if not pr:
                sys.stderr.write(f"fake gh: no PR #{{num}} in {{repo_name}}\\n"); sys.exit(1)
            # --body-file <path-or-dash>
            body_file = flag("--body-file")
            if body_file == "-":
                pr["body"] = sys.stdin.read()
                # gh strips trailing newlines on --body-file; mimic that.
                pr["body"] = pr["body"].rstrip("\\n")
            elif body_file:
                pr["body"] = open(body_file).read().rstrip("\\n")
            add_label = flag("--add-label")
            if add_label:
                labels = pr.setdefault("labels", [])
                if not any(l.get("name") == add_label for l in labels):
                    labels.append({{"name": add_label}})
            save(state)
            sys.exit(0)

        # --- gh pr create -------------------------------------------------
        if args[:2] == ["pr", "create"]:
            repo_name, repo = repo_from_flag(state)
            title = flag("--title") or "untitled"
            body  = flag("--body")  or ""
            head  = flag("--head")  or "branch"
            base  = flag("--base")  or repo["default_branch"]
            draft = "--draft" in args
            num = repo["next_pr_number"]
            repo["next_pr_number"] += 1
            repo["prs"][str(num)] = {{
                "number": num,
                "state": "OPEN",
                "isDraft": draft,
                "headRefName": head,
                "title": title,
                "body": body,
                "labels": [],
            }}
            save(state)
            print(f"https://github.com/{{repo_name}}/pull/{{num}}")
            sys.exit(0)

        # --- gh label create ---------------------------------------------
        if args[:2] == ["label", "create"]:
            repo_name, repo = repo_from_flag(state)
            # Positional label name is the first non-flag arg after `label create`.
            name = None
            i = 2
            while i < len(args):
                tok = args[i]
                if tok.startswith("--"):
                    i += 2
                    continue
                name = tok
                break
            if name and name not in repo["labels"]:
                repo["labels"].append(name)
            save(state)
            sys.exit(0)

        sys.stderr.write(f"fake gh: unhandled subcommand: {{args!r}}\\n")
        sys.exit(3)
    """).lstrip())
    fake_gh_py.chmod(fake_gh_py.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    old_path = os.environ.get("PATH", "")
    monkeypatch.setenv("PATH", f"{bin_dir}:{old_path}")
    yield bin_dir, state_path


def _load(state_path: Path) -> dict:
    return json.loads(state_path.read_text())


def _save(state_path: Path, state: dict) -> None:
    state_path.write_text(json.dumps(state, indent=2))


def seed_repo(state_path: Path, repo: str, *, default_branch: str = "main") -> None:
    state = _load(state_path)
    state.setdefault("repos", {})[repo] = {
        "default_branch": default_branch,
        "next_pr_number": 1,
        "labels": [],
        "prs": {},
    }
    _save(state_path, state)


def seed_pr(state_path: Path, repo: str, number: int, **kwargs) -> None:
    state = _load(state_path)
    r = state["repos"].setdefault(repo, {
        "default_branch": "main",
        "next_pr_number": number + 1,
        "labels": [],
        "prs": {},
    })
    defaults = {
        "number": number,
        "state": "OPEN",
        "isDraft": True,
        "headRefName": f"coordinator/test-{number}",
        "title": f"Test PR #{number}",
        "body": "",
        "labels": [],
    }
    defaults.update(kwargs)
    # Accept plain strings for labels list and coerce.
    if defaults["labels"] and isinstance(defaults["labels"][0], str):
        defaults["labels"] = [{"name": n} for n in defaults["labels"]]
    r["prs"][str(number)] = defaults
    r["next_pr_number"] = max(r["next_pr_number"], number + 1)
    _save(state_path, state)


def read_pr(state_path: Path, repo: str, number: int) -> dict:
    return _load(state_path)["repos"][repo]["prs"][str(number)]
