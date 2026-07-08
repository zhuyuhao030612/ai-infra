"""Token-based authentication for local-agent."""
from __future__ import annotations

import hmac
from fastapi import HTTPException, Header
from dotenv import load_dotenv

from app.config import settings

load_dotenv()

_DEFAULTS = {"local-agent-mvp-token-change-me", "high-risk-confirm-token-change-me", ""}


def _configured(secret: str, name: str) -> None:
    if settings.require_configured_tokens and secret in _DEFAULTS:
        raise HTTPException(status_code=503, detail=f"{name} is not configured securely")


def _extract_bearer(authorization: str) -> str:
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    return authorization.removeprefix("Bearer ").strip()


def verify_token(authorization: str = Header("")) -> None:
    """Normal auth — required for all non-public endpoints."""
    _configured(settings.agent_token, "AGENT_TOKEN")
    token = _extract_bearer(authorization)
    if not hmac.compare_digest(token, settings.agent_token):
        raise HTTPException(status_code=403, detail="Invalid token")


def verify_high_risk_token(x_high_risk_token: str = Header("")) -> None:
    """Extra auth — required for dangerous operations."""
    _configured(settings.high_risk_token, "HIGH_RISK_TOKEN")
    if not x_high_risk_token:
        raise HTTPException(status_code=401, detail="Missing X-High-Risk-Token header")
    if not hmac.compare_digest(x_high_risk_token, settings.high_risk_token):
        raise HTTPException(status_code=403, detail="Invalid high-risk token")
