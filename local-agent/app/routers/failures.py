"""Failure artifact browser — authenticated read-only access."""
from __future__ import annotations

import json
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException

from app.audit import new_request_id
from app.config import settings
from app.schemas import APIResponse
from app.security import verify_token

router = APIRouter(tags=["failures"])

FAILURES_DIR = settings.failures_dir.resolve()
MAX_TEXT_ARTIFACT_BYTES = 1 * 1024 * 1024


def _contained(root: Path, target: Path) -> bool:
    return root == target or root in target.parents


def _safe_path(failure_id: str, artifact: str | None = None) -> Path:
    if not failure_id or any(sep in failure_id for sep in ("..", "/", "\\", "\x00")):
        raise HTTPException(400, "Invalid failure ID")
    base = (FAILURES_DIR / failure_id).resolve()
    if not _contained(FAILURES_DIR, base):
        raise HTTPException(400, "Invalid path")
    if artifact is None:
        return base
    if not artifact or any(sep in artifact for sep in ("..", "/", "\\", "\x00")):
        raise HTTPException(400, "Invalid artifact name")
    path = (base / artifact).resolve()
    if not _contained(base, path):
        raise HTTPException(400, "Invalid artifact path")
    return path


@router.get("/failures/recent", response_model=APIResponse)
def recent_failures(limit: int = 10, _: None = Depends(verify_token)):
    rid = new_request_id()
    limit = max(1, min(limit, 100))
    if not FAILURES_DIR.exists():
        return APIResponse(request_id=rid, success=True, data={"failures": []})

    dirs = sorted([d for d in FAILURES_DIR.iterdir() if d.is_dir()], key=lambda d: d.stat().st_mtime, reverse=True)[:limit]
    result = []
    for d in dirs:
        manifest_file = d / "manifest.json"
        if manifest_file.exists():
            try:
                manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                manifest = {"id": d.name, "summary": "manifest parse error"}
        else:
            manifest = {"id": d.name, "summary": "no manifest"}
        result.append({
            "id": d.name,
            "ts": manifest.get("ts"),
            "source": manifest.get("source"),
            "error_type": manifest.get("error_type"),
            "summary": manifest.get("summary"),
            "ok": manifest.get("ok"),
        })
    return APIResponse(request_id=rid, success=True, data={"failures": result})


@router.get("/failures/{failure_id}/manifest", response_model=APIResponse)
def failure_manifest(failure_id: str, _: None = Depends(verify_token)):
    rid = new_request_id()
    path = _safe_path(failure_id) / "manifest.json"
    if not path.exists():
        raise HTTPException(404, "Manifest not found")
    manifest = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    return APIResponse(request_id=rid, success=True, data=manifest)


@router.get("/failures/{failure_id}/artifact/{name}", response_model=APIResponse)
def failure_artifact(failure_id: str, name: str, _: None = Depends(verify_token)):
    rid = new_request_id()
    path = _safe_path(failure_id, name)
    if not path.exists() or not path.is_file():
        raise HTTPException(404, f"Artifact '{name}' not found")
    file_size = path.stat().st_size
    if file_size > 100 * 1024 * 1024:
        raise HTTPException(413, "Artifact too large")

    if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}:
        return APIResponse(request_id=rid, success=True, data={"type": "image", "path": str(path), "size": file_size})

    try:
        if file_size > MAX_TEXT_ARTIFACT_BYTES:
            with path.open(encoding="utf-8", errors="replace") as f:
                content = f"[File too large: {file_size} bytes. First {MAX_TEXT_ARTIFACT_BYTES} chars shown.]\n\n" + f.read(MAX_TEXT_ARTIFACT_BYTES)
        else:
            content = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise HTTPException(500, "Cannot read artifact") from exc
    return APIResponse(request_id=rid, success=True, data={"type": "text", "name": name, "content": content, "size": file_size})
