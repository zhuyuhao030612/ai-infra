"""Process management — list and guarded terminate."""
from __future__ import annotations

import os

import psutil
from fastapi import APIRouter, Depends

from app.audit import audit_log, new_request_id
from app.errors import classify_exception
from app.schemas import APIResponse, ErrorCode, ProcessKillRequest, ProcessListItem, make_error
from app.security import verify_high_risk_token, verify_token

router = APIRouter(tags=["process"])
_PROTECTED_NAMES = {"system", "registry", "wininit.exe", "csrss.exe", "lsass.exe", "services.exe", "smss.exe"}


@router.post("/process/list", response_model=APIResponse)
def list_processes(_: None = Depends(verify_token)):
    rid = new_request_id()
    items = []
    for p in psutil.process_iter(["pid", "name", "exe", "username", "status"]):
        try:
            items.append(ProcessListItem(
                pid=p.info["pid"],
                name=p.info["name"] or "",
                exe=p.info["exe"],
                username=p.info["username"],
                status=p.info["status"] or "unknown",
            ))
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    audit_log(rid, "process_list", {"count": len(items)})
    return APIResponse(request_id=rid, success=True, data={"processes": [i.model_dump() for i in items]})


@router.post("/process/kill", response_model=APIResponse)
def kill_process(
    req: ProcessKillRequest,
    _token: None = Depends(verify_token),
    _hr: None = Depends(verify_high_risk_token),
):
    rid = new_request_id()
    if not req.risk_ack:
        return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.SECURITY_BLOCKED, "kill requires risk_ack=true", "Resubmit only after verifying PID/name."))
    if req.pid in {0, 4, os.getpid()}:
        return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.SECURITY_BLOCKED, "Refusing to kill protected PID"))
    try:
        p = psutil.Process(req.pid)
        name = p.name() or ""
        if name.lower() in _PROTECTED_NAMES:
            return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.SECURITY_BLOCKED, f"Refusing to kill protected process: {name}"))
        info = {"pid": req.pid, "name": name, "exe": p.exe(), "reason": req.reason}
        audit_log(rid, "process_kill_request", info)
        p.terminate()
        try:
            p.wait(timeout=5)
        except psutil.TimeoutExpired:
            audit_log(rid, "process_kill_timeout", {"pid": req.pid}, status="error")
            return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.TIMEOUT, f"Process {req.pid} did not terminate within 5s"))
        audit_log(rid, "process_kill_done", {"pid": req.pid})
        return APIResponse(request_id=rid, success=True, data={"killed": req.pid, "name": name})
    except psutil.NoSuchProcess:
        return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.NOT_FOUND, f"Process {req.pid} not found"))
    except psutil.AccessDenied:
        return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.PERMISSION_DENIED, f"Access denied for PID {req.pid}"))
    except Exception as e:
        audit_log(rid, "process_kill_failed", {"pid": req.pid, "error": str(e)}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(**classify_exception(e, "process_kill")))
