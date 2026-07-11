"""Audit logging — every operation leaves a redacted JSONL trace."""
from __future__ import annotations

import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.config import settings

LOG_DIR = Path(__file__).resolve().parent.parent / "logs"
LOG_FILE = LOG_DIR / "audit.jsonl"

_SECRET_KEYS = re.compile(r"password|passwd|pwd|pass|token|cookie|secret|api[_-]?key|authorization", re.I)
_SECRET_VALUE = re.compile(r"\b(Bearer\s+)[A-Za-z0-9._~+/=-]+", re.I)


def _ensure_log_dir() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)


def new_request_id() -> str:
    return f"req-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:6]}"


def _redact(value: Any, depth: int = 0) -> Any:
    if depth > 8:
        return "[DEPTH_LIMIT]"
    if isinstance(value, str):
        text = value
        for secret in (settings.agent_token, settings.high_risk_token):
            if secret:
                text = text.replace(secret, "[REDACTED_SECRET]")
        return _SECRET_VALUE.sub(r"\1[REDACTED_TOKEN]", text)
    if isinstance(value, bytes):
        return f"[BYTES:{len(value)}]"
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key)
            out[key_text] = "[REDACTED_SECRET]" if _SECRET_KEYS.search(key_text) else _redact(item, depth + 1)
        return out
    if isinstance(value, (list, tuple, set)):
        return [_redact(item, depth + 1) for item in list(value)[:200]]
    return value


def audit_log(request_id: str, action: str, details: dict | None = None, status: str = "ok") -> None:
    """Write one redacted JSON line to the audit log."""
    _ensure_log_dir()
    safe_details = _redact(details or {})
    raw = json.dumps(safe_details, ensure_ascii=False)
    if len(raw.encode("utf-8")) > settings.max_audit_detail_bytes:
        safe_details = {"truncated": True, "preview": raw[: settings.max_audit_detail_bytes // 2]}
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "pid": os.getpid(),
        "request_id": request_id,
        "action": action,
        "status": status,
        "details": safe_details,
    }
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
