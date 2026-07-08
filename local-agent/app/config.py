"""Central runtime configuration for local-agent."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable


def _split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def _int_env(name: str, default: int, minimum: int, maximum: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer") from exc
    if value < minimum or value > maximum:
        raise RuntimeError(f"{name} must be between {minimum} and {maximum}")
    return value


def _default_roots() -> list[str]:
    candidates = [
        r"D:\Code",
        r"D:\PHS",
        r"C:\Users\ZHUYU\Desktop",
        r"C:\Users\ZHUYU\Documents",
    ]
    return [item for item in candidates if Path(item).exists()]


class Settings:
    """Small dependency-free settings object.

    Environment variables are intentionally read once at import time so that audit and
    security decisions are stable during a process lifetime.
    """

    agent_token: str = os.getenv("AGENT_TOKEN", "")
    high_risk_token: str = os.getenv("HIGH_RISK_TOKEN", "")
    require_configured_tokens: bool = os.getenv("ALLOW_DEFAULT_AGENT_TOKENS", "0").lower() not in {"1", "true", "yes"}

    allowed_origins: list[str] = _split_csv(os.getenv("LOCAL_AGENT_ALLOWED_ORIGINS")) or [
        "http://127.0.0.1:9000",
        "http://localhost:9000",
    ]
    allowed_roots: list[Path] = [Path(p).resolve() for p in (_split_csv(os.getenv("LOCAL_AGENT_ALLOWED_ROOTS")) or _default_roots())]

    screenshots_dir: Path = Path(os.getenv("LOCAL_AGENT_SCREENSHOTS_DIR", r"D:\Code\screenshots")).resolve()
    failures_dir: Path = Path(os.getenv("LOCAL_AGENT_FAILURES_DIR", r"D:\Code\ai-infra\failures")).resolve()

    max_file_read_bytes: int = _int_env("LOCAL_AGENT_MAX_FILE_READ_BYTES", 5 * 1024 * 1024, 1024, 100 * 1024 * 1024)
    max_exec_timeout_sec: int = _int_env("LOCAL_AGENT_MAX_EXEC_TIMEOUT_SEC", 120, 1, 3600)
    max_exec_stdout_bytes: int = _int_env("LOCAL_AGENT_MAX_EXEC_STDOUT_BYTES", 64 * 1024, 1024, 10 * 1024 * 1024)
    max_exec_stderr_bytes: int = _int_env("LOCAL_AGENT_MAX_EXEC_STDERR_BYTES", 32 * 1024, 1024, 10 * 1024 * 1024)
    max_audit_detail_bytes: int = _int_env("LOCAL_AGENT_MAX_AUDIT_DETAIL_BYTES", 16 * 1024, 1024, 1024 * 1024)
    max_search_results: int = _int_env("LOCAL_AGENT_MAX_SEARCH_RESULTS", 200, 1, 5000)

    @property
    def effective_allowed_roots(self) -> list[Path]:
        roots = list(self.allowed_roots)
        for extra in (self.screenshots_dir, self.failures_dir):
            if extra not in roots:
                roots.append(extra)
        return roots


settings = Settings()


def ensure_runtime_dirs(paths: Iterable[Path] | None = None) -> None:
    for p in (paths or (settings.screenshots_dir, settings.failures_dir)):
        p.mkdir(parents=True, exist_ok=True)
