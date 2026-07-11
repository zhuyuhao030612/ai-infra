"""Local Agent — FastAPI app entry point."""
from __future__ import annotations

import shutil
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.responses import RedirectResponse

from app.audit import LOG_DIR, LOG_FILE, new_request_id
from app.config import ensure_runtime_dirs, settings
from app.routers import desktop, exec as exec_router, failures as failures_router, files, process, search, status as status_router, windows as windows_router
from app.schemas import APIResponse

app = FastAPI(title="Local Agent", version="0.2.0-hardening")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "X-High-Risk-Token", "Content-Type"],
)

app.include_router(process.router)
app.include_router(files.router)
app.include_router(exec_router.router)
app.include_router(desktop.router)
app.include_router(search.router)
app.include_router(status_router.router)
app.include_router(windows_router.router)
app.include_router(failures_router.router)

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
STATIC_DIR.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR), html=True), name="static")


@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse(url="/static/index.html")


@app.on_event("startup")
def startup_tasks() -> None:
    """Prepare runtime dirs and rotate audit log if larger than 10 MB."""
    ensure_runtime_dirs()
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    max_bytes = 10 * 1024 * 1024
    if LOG_FILE.exists() and LOG_FILE.stat().st_size > max_bytes:
        backup = LOG_DIR / f"audit-{LOG_FILE.stat().st_mtime:.0f}.jsonl"
        shutil.move(str(LOG_FILE), str(backup))


@app.get("/health", response_model=APIResponse)
def health():
    return APIResponse(request_id=new_request_id(), success=True, data={"status": "ok"})
