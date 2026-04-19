"""Execution scheme / storage contract tests (no gh calls)."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

SCHEME_PY = Path(__file__).resolve().parent.parent / "artifact-schemes" / "execution" / "scheme.py"
STORAGE_PY = (
    Path(__file__).resolve().parent.parent / "artifact-storage" / "execution-gh-pr" / "storage.py"
)


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def test_scheme_exports_expected_subcommands():
    mod = _load("execution_scheme", SCHEME_PY)
    scheme = mod.SCHEME
    expected = {"create", "get", "update", "list", "status", "progress", "lock", "release"}
    assert set(scheme.subcommands.keys()) == expected


def test_scheme_create_requires_workflow():
    mod = _load("execution_scheme", SCHEME_PY)
    scheme = mod.SCHEME
    create_in = scheme.subcommands["create"].in_model
    with pytest.raises(Exception):
        create_in.model_validate({})


def test_storage_parses_uri():
    mod = _load("execution_storage", STORAGE_PY)
    pr = mod._parse_uri("execution|execution-gh-pr/acme/repo/42")
    assert pr.owner == "acme"
    assert pr.repo == "repo"
    assert pr.number == 42


def test_storage_rejects_bad_uri():
    mod = _load("execution_storage", STORAGE_PY)
    with pytest.raises(mod.StorageError):
        mod._parse_uri("execution|local-filesystem/acme/repo/42")
