"""Failure classifier — map raw exceptions to structured ErrorDetail."""
from __future__ import annotations

import subprocess

from app.schemas import ErrorCode, make_error


def classify_exception(e: Exception, context: str = "") -> dict:
    """Classify any exception into a structured error dict."""
    msg = str(e)
    msg_lower = msg.lower()

    if any(k in msg_lower for k in ("permission denied", "access denied", "access is denied", "0x80070005", "requires elevation", "run as administrator")):
        return make_error(ErrorCode.PERMISSION_DENIED, msg, "Run PowerShell as Administrator or use elevated token").model_dump()

    if any(k in msg_lower for k in ("no such file", "not found", "cannot find", "does not exist")):
        if any(ext in msg_lower for ext in (".py", ".ps1", ".js")):
            return make_error(ErrorCode.ENV_ERROR, msg, "Missing script or runtime file. Check deployment.").model_dump()
        return make_error(ErrorCode.NOT_FOUND, msg, "Check the path and try again").model_dump()

    if any(k in msg_lower for k in ("not recognized", "is not recognized", "command not found", "no module named", "importerror", "modulenotfound")):
        return make_error(ErrorCode.ENV_ERROR, msg, "Install missing dependency or use full path").model_dump()

    if any(k in msg_lower for k in ("timeout", "timed out", "timedout")):
        return make_error(ErrorCode.TIMEOUT, msg, "Increase timeout or check network/service status").model_dump()

    if any(k in msg_lower for k in ("address already in use", "port already", "bind")):
        return make_error(ErrorCode.RUNTIME_ERROR, msg, "Port is occupied. Kill the existing process or use a different port.").model_dump()

    if any(k in msg_lower for k in ("window not found", "no visible window", "no window", "mainwindowhandle", "findwindow")):
        return make_error(ErrorCode.WINDOW_NOT_FOUND, msg, "No visible window for this process. Use /windows to verify.").model_dump()

    if any(k in msg_lower for k in ("uia", "automation", "invokepattern", "valuepattern")):
        return make_error(ErrorCode.UIA_FAILED, msg, "UIA failed. Fall back to screenshot + Vision or human confirmation.").model_dump()

    if any(k in msg_lower for k in ("locked", "already running", "state", "stale", "duplicate")):
        return make_error(ErrorCode.STATE_CONFLICT, msg, "A conflicting operation is in progress. Wait and retry, or clean up stale state.").model_dump()

    if isinstance(e, subprocess.CalledProcessError):
        stderr = (e.stderr or "")[:200]
        return make_error(ErrorCode.RUNTIME_ERROR, f"Command exited with {e.returncode}: {stderr or msg}", "Check stderr output for details").model_dump()

    if any(k in msg_lower for k in ("json", "decode", "parse", "invalid format")):
        return make_error(ErrorCode.INVALID_INPUT, msg, "The data format is invalid. Check malformed JSON or unescaped characters.").model_dump()

    return make_error(ErrorCode.INTERNAL_ERROR, f"{context + ': ' if context else ''}{msg}", "Unexpected error. Check logs and failure artifacts.").model_dump()


def classify_subprocess(result: subprocess.CompletedProcess, context: str = "") -> dict | None:
    if result.returncode == 0:
        return None
    stderr = (result.stderr or "")[:500]
    text = stderr.lower()
    if "denied" in text or "access" in text:
        return make_error(ErrorCode.PERMISSION_DENIED, stderr.strip() or "Permission denied", "Run as Administrator").model_dump()
    if "not found" in text or "not recognized" in text:
        return make_error(ErrorCode.ENV_ERROR, stderr.strip() or "Command not found", "Install the required tool or use full path").model_dump()
    if "timeout" in text:
        return make_error(ErrorCode.TIMEOUT, stderr.strip() or "Command timed out", "Increase timeout or simplify the operation").model_dump()
    return make_error(ErrorCode.RUNTIME_ERROR, f"Exit {result.returncode}: {stderr.strip()[:200]}", "Check command output for details").model_dump()
