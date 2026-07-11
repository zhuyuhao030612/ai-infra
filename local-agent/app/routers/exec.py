"""Command execution — guarded shell execution with timeout and audit."""
from __future__ import annotations

import os
import platform
import re
import subprocess
from pathlib import Path

from fastapi import APIRouter, Depends

from app.audit import audit_log, new_request_id
from app.config import settings
from app.errors import classify_exception
from app.path_utils import resolve_allowed_path
from app.schemas import APIResponse, ErrorCode, ExecRequest, make_error
from app.security import verify_high_risk_token, verify_token

router = APIRouter(tags=["exec"])

_DESTRUCTIVE = re.compile(
    r"\b("
    r"rm\s+-rf|Remove-Item\b|del\b|erase\b|rmdir\b|format\b|diskpart\b|"
    r"shutdown\b|Restart-Computer\b|Stop-Computer\b|Stop-Process\b|kill\b|taskkill\b|"
    r"reg\s+delete|Set-ExecutionPolicy\b|icacls\b|takeown\b|"
    r"git\s+reset\b"
    r")",
    re.I,
)


def _tail_text(text: str, max_bytes: int) -> str:
    encoded = text.encode("utf-8", errors="replace")
    if len(encoded) <= max_bytes:
        return text
    return encoded[-max_bytes:].decode("utf-8", errors="replace")


def _safe_env() -> dict[str, str]:
    keep = {"PATH", "PATHEXT", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "USERPROFILE", "USERNAME", "COMSPEC", "HOME", "LANG"}
    return {key: value for key, value in os.environ.items() if key.upper() in keep}


def _build_command(command: str) -> list[str]:
    if platform.system().lower() == "windows":
        shell = "pwsh" if shutil_which("pwsh") else "powershell.exe"
        return [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command]
    return ["bash", "-lc", command]


def shutil_which(name: str) -> str | None:
    from shutil import which

    return which(name)


@router.post("/exec", response_model=APIResponse)
def execute_command(
    req: ExecRequest,
    _token: None = Depends(verify_token),
    _hr: None = Depends(verify_high_risk_token),
):
    rid = new_request_id()
    timeout = min(req.timeout, settings.max_exec_timeout_sec)

    if not req.risk_ack:
        return APIResponse(
            request_id=rid,
            success=False,
            error=make_error(ErrorCode.SECURITY_BLOCKED, "exec requires risk_ack=true", "Resubmit only after checking the command and expected working directory."),
        )
    if not req.run_id:
        return APIResponse(
            request_id=rid,
            success=False,
            error=make_error(ErrorCode.INVALID_INPUT, "exec requires run_id", "Tie every command to the current task/run id for auditability."),
        )

    working_dir: Path | None = None
    try:
        if req.working_dir:
            working_dir = resolve_allowed_path(req.working_dir, must_exist=True, allow_dir=True)
            if not working_dir.is_dir():
                return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.INVALID_INPUT, "working_dir must be a directory"))
        if _DESTRUCTIVE.search(req.command):
            audit_log(rid, "exec_destructive_command", {"run_id": req.run_id, "command": req.command, "cwd": str(working_dir or "")}, status="blocked")
            return APIResponse(
                request_id=rid,
                success=False,
                error=make_error(ErrorCode.SECURITY_BLOCKED, "Destructive command blocked by security filter", "The command matches a destructive pattern. Use a non-destructive alternative."),
            )

        audit_log(rid, "exec_request", {"run_id": req.run_id, "command": req.command, "timeout": timeout, "cwd": str(working_dir or "")})
        result = subprocess.run(
            _build_command(req.command),
            shell=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(working_dir) if working_dir else None,
            env=_safe_env(),
            encoding="utf-8",
            errors="replace",
        )
        audit_log(rid, "exec_done", {"run_id": req.run_id, "exit_code": result.returncode})
        return APIResponse(
            request_id=rid,
            success=result.returncode == 0,
            data={
                "exit_code": result.returncode,
                "stdout": _tail_text(result.stdout or "", settings.max_exec_stdout_bytes),
                "stderr": _tail_text(result.stderr or "", settings.max_exec_stderr_bytes),
                "stdout_truncated": len((result.stdout or "").encode("utf-8", errors="replace")) > settings.max_exec_stdout_bytes,
                "stderr_truncated": len((result.stderr or "").encode("utf-8", errors="replace")) > settings.max_exec_stderr_bytes,
            },
        )
    except subprocess.TimeoutExpired:
        audit_log(rid, "exec_timeout", {"run_id": req.run_id, "timeout": timeout}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.TIMEOUT, f"Command timed out after {timeout}s", "Increase timeout or simplify the operation."))
    except Exception as e:
        audit_log(rid, "exec_failed", {"run_id": req.run_id, "error": str(e)}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(**classify_exception(e, "exec")))
