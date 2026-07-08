"""File operations — bounded read and safe-delete via Recycle Bin."""
from __future__ import annotations

from fastapi import APIRouter, Depends
import send2trash

from app.audit import audit_log, new_request_id
from app.config import settings
from app.errors import classify_exception
from app.path_utils import resolve_allowed_path
from app.schemas import APIResponse, ErrorCode, FilePathRequest, FileReadResponse, make_error
from app.security import verify_high_risk_token, verify_token

router = APIRouter(tags=["files"])


@router.post("/files/read", response_model=APIResponse)
def read_file(req: FilePathRequest, _: None = Depends(verify_token)):
    rid = new_request_id()
    try:
        path = resolve_allowed_path(req.path, must_exist=True, allow_dir=False)
        size = path.stat().st_size
        limit = min(req.max_bytes or settings.max_file_read_bytes, settings.max_file_read_bytes)
        if size > limit:
            with path.open("rb") as f:
                raw = f.read(limit)
            content = raw.decode("utf-8", errors="replace")
            truncated = True
        else:
            content = path.read_text(encoding="utf-8", errors="replace")
            truncated = False
        audit_log(rid, "file_read", {"path": str(path), "size": size, "truncated": truncated})
        return APIResponse(
            request_id=rid,
            success=True,
            data=FileReadResponse(path=str(path), size=size, content=content, truncated=truncated).model_dump(),
        )
    except Exception as e:
        audit_log(rid, "file_read_failed", {"path": req.path, "error": str(e)}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(**classify_exception(e, "file_read")))


@router.post("/files/delete", response_model=APIResponse)
def delete_file(
    req: FilePathRequest,
    _token: None = Depends(verify_token),
    _hr: None = Depends(verify_high_risk_token),
):
    rid = new_request_id()
    if not req.risk_ack:
        return APIResponse(
            request_id=rid,
            success=False,
            error=make_error(ErrorCode.SECURITY_BLOCKED, "delete requires risk_ack=true", "Resubmit only after verifying the path."),
        )
    try:
        path = resolve_allowed_path(req.path, must_exist=True, allow_dir=False)
        stat = path.stat()
        audit_log(rid, "file_delete_request", {"path": str(path), "size": stat.st_size})
        send2trash.send2trash(str(path))
        audit_log(rid, "file_delete_done", {"path": str(path)})
        return APIResponse(request_id=rid, success=True, data={"deleted": str(path), "method": "recycle_bin"})
    except Exception as e:
        audit_log(rid, "file_delete_failed", {"path": req.path, "error": str(e)}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(**classify_exception(e, "file_delete")))
