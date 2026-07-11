"""Window info — router → service architecture."""
from __future__ import annotations

import subprocess

from fastapi import APIRouter, Depends

from app.audit import new_request_id
from app.schemas import APIResponse, ErrorCode, make_error
from app.security import verify_token
from app.services.window_service import get_windows

router = APIRouter(tags=["windows"])


@router.get("/windows", response_model=APIResponse)
def list_windows(_: None = Depends(verify_token)):
    rid = new_request_id()
    try:
        wins = get_windows()
    except subprocess.TimeoutExpired:
        return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.TIMEOUT, "PowerShell window query timed out", "Retry or check if pwsh is responsive"))
    except FileNotFoundError:
        return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.ENV_ERROR, "pwsh/powershell not found in PATH", "Install PowerShell 7+ or use full path"))
    except Exception as e:
        return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.RUNTIME_ERROR, str(e), "Check local-agent logs for details"))
    return APIResponse(request_id=rid, success=True, data={"windows": wins, "count": len(wins)})
