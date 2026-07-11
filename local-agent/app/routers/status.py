"""System status v2 — TTL cache + tail read + JSON/ts tolerance."""
from __future__ import annotations

import json
import time as _time
from collections import deque
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import APIRouter, Depends

from app.audit import LOG_FILE, new_request_id
from app.schemas import APIResponse
from app.security import verify_token

router = APIRouter(tags=["status"])

SERVER_START = datetime.now(timezone.utc)
EVENTS_LOG = Path("D:/Code/ai-infra/logs/events.jsonl")
WATCHDOG_LOG = Path("D:/Code/local-agent/logs/watchdog.log")
GPT_LOGS = [Path("D:/Code/ai-pipeline/gpt55-stdout.log"), Path("D:/Code/ai-pipeline/gpt55-stderr.log")]

_STATUS_CACHE: dict = {"ts": 0.0, "data": None}
STATUS_TTL_SEC = 3
MAX_EVENT_LINES = 5000


def _parse_ts(value: object) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        ts = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return ts.astimezone(timezone.utc)


def _read_events(since_hours: int = 24) -> list[dict]:
    now = _time.time()
    if now - _STATUS_CACHE["ts"] < STATUS_TTL_SEC and _STATUS_CACHE["data"] is not None:
        return list(_STATUS_CACHE["data"])
    if not EVENTS_LOG.exists():
        _STATUS_CACHE.update({"ts": now, "data": []})
        return []

    cutoff = datetime.now(timezone.utc) - timedelta(hours=since_hours)
    lines = deque(maxlen=MAX_EVENT_LINES)
    try:
        with EVENTS_LOG.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                stripped = line.strip()
                if stripped:
                    lines.append(stripped)
    except OSError:
        _STATUS_CACHE.update({"ts": now, "data": []})
        return []

    events: list[dict] = []
    for line in lines:
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        ts = _parse_ts(ev.get("ts"))
        if ts is not None and ts >= cutoff:
            events.append(ev)
    _STATUS_CACHE.update({"ts": now, "data": events})
    return list(events)


def _from_events() -> dict | None:
    events = _read_events(24)
    if not events:
        return None
    by_type: dict[str, list] = {}
    for ev in events:
        by_type.setdefault(ev.get("type", "unknown"), []).append(ev)
    gpt_asks = by_type.get("gpt.ask", [])
    gpt_ok = sum(1 for e in gpt_asks if e.get("ok"))
    smoke_runs = by_type.get("smoke.run", [])
    verify_runs = by_type.get("verify.run", [])
    last_smoke = smoke_runs[-1] if smoke_runs else None
    last_verify = verify_runs[-1] if verify_runs else None
    return {
        "gpt": {"success_rate_24h": round(gpt_ok / len(gpt_asks) * 100, 1) if gpt_asks else None, "total_24h": len(gpt_asks), "ok_24h": gpt_ok},
        "smoke": {"last_ok": last_smoke.get("ok"), "last_run": last_smoke.get("ts"), "last_passed": last_smoke.get("passed")} if last_smoke else None,
        "verify": {"last_ok": last_verify.get("ok"), "last_run": last_verify.get("ts"), "last_project": last_verify.get("project")} if last_verify else None,
        "total_events_24h": len(events),
    }


def _fallback_watchdog_restarts() -> int:
    if not WATCHDOG_LOG.exists():
        return 0
    try:
        return WATCHDOG_LOG.read_text(encoding="utf-8", errors="replace").count("RESTART #")
    except OSError:
        return 0


def _fallback_gpt_running() -> bool:
    try:
        newest = max((p.stat().st_mtime for p in GPT_LOGS if p.exists()), default=0)
        return newest > 0 and datetime.now() - datetime.fromtimestamp(newest) < timedelta(minutes=10)
    except OSError:
        return False


def _count_audit_requests() -> int:
    if not LOG_FILE.exists():
        return 0
    try:
        with LOG_FILE.open(encoding="utf-8", errors="replace") as f:
            return sum(1 for _ in f)
    except OSError:
        return 0


@router.get("/status", response_model=APIResponse)
def system_status():
    rid = new_request_id()
    uptime_sec = int((datetime.now(timezone.utc) - SERVER_START).total_seconds())
    h, m = divmod(uptime_sec // 60, 60)
    return APIResponse(request_id=rid, success=True, data={"health": "ok", "uptime": f"{h}h {m}m", "uptime_sec": uptime_sec})


@router.get("/status/full", response_model=APIResponse)
def system_status_full(_: None = Depends(verify_token)):
    rid = new_request_id()
    uptime_sec = int((datetime.now(timezone.utc) - SERVER_START).total_seconds())
    h, m = divmod(uptime_sec // 60, 60)
    event_data = _from_events()
    data: dict = {"health": "ok", "uptime": f"{h}h {m}m", "uptime_sec": uptime_sec, "requests_total": _count_audit_requests(), "watchdog_restarts": _fallback_watchdog_restarts()}
    if event_data:
        data.update({"gpt": event_data.get("gpt"), "smoke": event_data.get("smoke"), "verify": event_data.get("verify"), "total_events_24h": event_data.get("total_events_24h"), "events_window": {"max_lines": MAX_EVENT_LINES, "approximate": True}})
    else:
        data["gpt"] = {"running": _fallback_gpt_running(), "success_rate_24h": None}
        data["note"] = "no events — file-scan fallback"
    return APIResponse(request_id=rid, success=True, data=data)
