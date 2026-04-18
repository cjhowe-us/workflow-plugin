"""execution vertex scheme — a running or completed workflow instance."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

from artifactlib.kinds import Kind
from artifactlib.scheme import Scheme, Subcommand


ExecutionStatus = Literal["running", "needs_attention", "aborted", "complete"]


class ExecutionContent(BaseModel):
    workflow: str
    workflow_inputs: dict[str, Any] = Field(default_factory=dict)
    parent_execution: str | None = None
    owner: str | None = None
    status: ExecutionStatus = "running"
    title: str | None = None
    body: str | None = None
    assignees: list[str] = Field(default_factory=list)
    url: str | None = None


class CreateIn(BaseModel):
    workflow: str
    workflow_inputs: dict[str, Any] = Field(default_factory=dict)
    owner: str | None = None
    parent_execution: str | None = None
    title: str | None = None
    summary: str | None = None
    repo: str | None = None
    base: str | None = None
    head: str | None = None


class CreateOut(BaseModel):
    uri: str
    created: bool = True


class GetIn(BaseModel):
    uri: str


class GetOut(BaseModel):
    uri: str
    content: ExecutionContent
    edges: list[dict[str, Any]] = Field(default_factory=list)


class UpdateIn(BaseModel):
    uri: str
    patch: dict[str, Any] = Field(default_factory=dict)


class UpdateOut(BaseModel):
    uri: str
    updated: bool


class ListFilter(BaseModel):
    filter: dict[str, Any] = Field(default_factory=dict)


class ListOut(BaseModel):
    entries: list[dict[str, Any]] = Field(default_factory=list)


class LockIn(BaseModel):
    uri: str
    owner: str


class LockOut(BaseModel):
    held: bool
    current_owner: str | None = None


class ReleaseIn(BaseModel):
    uri: str
    owner: str


class ReleaseOut(BaseModel):
    released: bool


class StatusIn(BaseModel):
    uri: str


class StatusOut(BaseModel):
    uri: str
    status: ExecutionStatus


class ProgressIn(BaseModel):
    uri: str
    append: dict[str, Any] | None = None


class ProgressOut(BaseModel):
    entries: list[dict[str, Any]] = Field(default_factory=list)
    appended: bool = False


SCHEME = Scheme(
    kind=Kind.VERTEX,
    name="execution",
    contract_version=1,
    content_model=ExecutionContent,
    subcommands={
        "create":   Subcommand(in_model=CreateIn,   out_model=CreateOut,   required=True),
        "get":      Subcommand(in_model=GetIn,      out_model=GetOut,      required=True),
        "update":   Subcommand(in_model=UpdateIn,   out_model=UpdateOut,   required=True),
        "list":     Subcommand(in_model=ListFilter, out_model=ListOut,     required=True),
        "status":   Subcommand(in_model=StatusIn,   out_model=StatusOut,   required=True),
        "progress": Subcommand(in_model=ProgressIn, out_model=ProgressOut, required=True),
        "lock":     Subcommand(in_model=LockIn,     out_model=LockOut,     required=False),
        "release":  Subcommand(in_model=ReleaseIn,  out_model=ReleaseOut,  required=False),
    },
)
