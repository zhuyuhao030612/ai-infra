"""Path validation helpers for local-agent."""
from __future__ import annotations

from pathlib import Path
from fastapi import HTTPException

from app.config import settings


def _commonpath_contains(root: Path, target: Path) -> bool:
    try:
        return root == target or root in target.parents
    except RuntimeError:
        return False


def resolve_allowed_path(raw_path: str, *, must_exist: bool = False, allow_dir: bool = True) -> Path:
    if not isinstance(raw_path, str) or not raw_path.strip() or "\x00" in raw_path:
        raise HTTPException(status_code=400, detail="Invalid path")
    try:
        target = Path(raw_path).expanduser().resolve()
    except OSError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid path: {exc}") from exc

    if not any(_commonpath_contains(root, target) for root in settings.effective_allowed_roots):
        raise HTTPException(status_code=403, detail="Path is outside LOCAL_AGENT_ALLOWED_ROOTS")
    if must_exist and not target.exists():
        raise HTTPException(status_code=404, detail="Path not found")
    if not allow_dir and target.exists() and target.is_dir():
        raise HTTPException(status_code=400, detail="Path is a directory")
    return target


def safe_child_path(root: Path, name: str) -> Path:
    if not isinstance(name, str) or not name.strip() or "\x00" in name:
        raise HTTPException(status_code=400, detail="Invalid filename")
    clean = Path(name).name
    if clean in {"", ".", ".."} or clean != name:
        raise HTTPException(status_code=400, detail="Filename must be a single safe path segment")
    target = (root / clean).resolve()
    if root.resolve() != target and root.resolve() not in target.parents:
        raise HTTPException(status_code=400, detail="Path escapes target directory")
    return target
