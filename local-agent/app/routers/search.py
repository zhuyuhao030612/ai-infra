"""File search — bounded filename search plus optional content grep."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.audit import audit_log, new_request_id
from app.config import settings
from app.schemas import APIResponse
from app.security import verify_token

router = APIRouter(tags=["search"])

_SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".mypy_cache", ".ruff_cache", "dist", "build"}


class SearchRequest(BaseModel):
    query: str = Field(min_length=1, max_length=200)
    max_results: int = Field(default=50, ge=1, le=5000)
    search_content: bool = False


def _search_filename(query: str, max_results: int) -> list[dict]:
    results: list[dict] = []
    needle = query.lower()
    for root in settings.allowed_roots:
        if not root.exists() or len(results) >= max_results:
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in _SKIP_DIRS]
            for name in filenames:
                if needle not in name.lower():
                    continue
                p = Path(dirpath) / name
                try:
                    stat = p.stat()
                    results.append({"path": str(p), "name": p.name, "size": stat.st_size, "modified": stat.st_mtime})
                except OSError:
                    results.append({"path": str(p), "name": p.name, "size": 0, "modified": 0})
                if len(results) >= max_results:
                    return results
    return results


def _search_content(pattern: str, max_results: int) -> list[dict]:
    results: list[dict] = []
    for root in settings.allowed_roots:
        if not root.exists() or len(results) >= max_results:
            continue
        try:
            proc = subprocess.run(
                ["findstr", "/s", "/i", "/m", "/c:" + pattern, str(root / "*")],
                capture_output=True,
                text=True,
                timeout=30,
                encoding="utf-8",
                errors="replace",
            )
            for line in proc.stdout.strip().splitlines():
                line = line.strip()
                if line and len(results) < max_results:
                    results.append({"path": line, "name": Path(line).name, "match": "content"})
        except Exception:
            continue
    return results


@router.post("/search", response_model=APIResponse)
def search_files(req: SearchRequest, _: None = Depends(verify_token)):
    rid = new_request_id()
    max_results = min(req.max_results, settings.max_search_results)
    audit_log(rid, "search", {"query": req.query, "max": max_results, "content": req.search_content})
    results = _search_filename(req.query, max_results)
    if req.search_content and len(results) < max_results:
        results.extend(_search_content(req.query, max_results - len(results)))
    return APIResponse(request_id=rid, success=True, data={"query": req.query, "count": len(results), "results": results})
