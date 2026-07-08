"""Unified API models — consistent error model for all endpoints."""
from __future__ import annotations

from typing import Any, Optional
from pydantic import BaseModel, Field


class ErrorDetail(BaseModel):
    """Structured error — machine-readable code + human message + next action."""

    code: str
    message: str
    next_action: Optional[str] = None


class APIResponse(BaseModel):
    request_id: str
    success: bool
    data: Optional[Any] = None
    error: Optional[ErrorDetail] = None


class ErrorCode:
    INVALID_INPUT = "INVALID_INPUT"
    NOT_FOUND = "NOT_FOUND"
    PERMISSION_DENIED = "PERMISSION_DENIED"
    ENV_ERROR = "ENV_ERROR"
    RUNTIME_ERROR = "RUNTIME_ERROR"
    TIMEOUT = "TIMEOUT"
    STATE_CONFLICT = "STATE_CONFLICT"
    EXTERNAL_UNAVAILABLE = "EXTERNAL_UNAVAILABLE"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    WINDOW_NOT_FOUND = "WINDOW_NOT_FOUND"
    UIA_FAILED = "UIA_FAILED"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    SECURITY_BLOCKED = "SECURITY_BLOCKED"


class ProcessKillRequest(BaseModel):
    pid: int = Field(ge=1)
    reason: Optional[str] = Field(default="No reason provided", max_length=500)
    risk_ack: bool = False


class ProcessListItem(BaseModel):
    pid: int
    name: str
    exe: Optional[str] = None
    username: Optional[str] = None
    status: str


class FilePathRequest(BaseModel):
    path: str = Field(min_length=1, max_length=4096)
    risk_ack: bool = False
    max_bytes: Optional[int] = Field(default=None, ge=1)


class FileReadResponse(BaseModel):
    path: str
    size: int
    content: str
    truncated: bool = False


class ExecRequest(BaseModel):
    command: str = Field(min_length=1, max_length=8000)
    timeout: int = Field(default=30, ge=1, le=3600)
    working_dir: Optional[str] = Field(default=None, max_length=4096)
    risk_ack: bool = False
    run_id: Optional[str] = Field(default=None, max_length=200)


def make_error(code: str, message: str, next_action: str | None = None) -> ErrorDetail:
    return ErrorDetail(code=code, message=message, next_action=next_action)
