"""Desktop UI automation — pyautogui for mouse/keyboard."""
from __future__ import annotations

import base64
import io

import pyautogui
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator

from app.audit import audit_log, new_request_id
from app.config import settings
from app.errors import classify_exception
from app.path_utils import safe_child_path
from app.schemas import APIResponse, ErrorCode, make_error
from app.security import verify_high_risk_token, verify_token

router = APIRouter(tags=["desktop"])

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.1


class ScreenshotRequest(BaseModel):
    region: tuple[int, int, int, int] | None = None

    @field_validator("region")
    @classmethod
    def validate_region(cls, value):
        if value is None:
            return value
        x, y, w, h = value
        if min(x, y, w, h) < 0 or w == 0 or h == 0 or w * h > 20_000_000:
            raise ValueError("Invalid screenshot region")
        return value


class ClickRequest(BaseModel):
    x: int = Field(ge=0, le=100000)
    y: int = Field(ge=0, le=100000)
    button: str = Field(default="left", pattern="^(left|right|middle)$")
    clicks: int = Field(default=1, ge=1, le=5)


class TypeRequest(BaseModel):
    text: str = Field(min_length=1, max_length=10000)
    interval: float = Field(default=0.05, ge=0, le=1)


class HotkeyRequest(BaseModel):
    keys: str = Field(min_length=1, max_length=100)

    @field_validator("keys")
    @classmethod
    def validate_keys(cls, value: str) -> str:
        parts = [part.strip().lower() for part in value.split("+") if part.strip()]
        if not parts or len(parts) > 5:
            raise ValueError("Invalid hotkey")
        allowed = {"ctrl", "control", "alt", "shift", "win", "cmd", "command", "tab", "enter", "esc", "escape", "space", "backspace", "delete", "home", "end", "pageup", "pagedown", "up", "down", "left", "right", "c", "v", "x", "a", "s", "z", "y", "f4", "f5"}
        if any(part not in allowed and not (len(part) == 1 and part.isalnum()) for part in parts):
            raise ValueError("Hotkey contains unsupported key")
        return "+".join(parts)


@router.post("/desktop/screenshot", response_model=APIResponse)
def take_screenshot(req: ScreenshotRequest | None = None, _: None = Depends(verify_token)):
    rid = new_request_id()
    try:
        region = req.region if req else None
        img = pyautogui.screenshot(region=region)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        raw = buf.getvalue()
        b64 = base64.b64encode(raw).decode()
        audit_log(rid, "desktop_screenshot", {"region": region, "bytes": len(raw)})
        return APIResponse(request_id=rid, success=True, data={"format": "png", "base64": b64, "bytes": len(raw)})
    except Exception as e:
        audit_log(rid, "desktop_screenshot_failed", {"error": str(e)}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(**classify_exception(e)))


@router.post("/desktop/screenshot/file", response_model=APIResponse)
def save_screenshot_file(filename: str = "screenshot.png", _: None = Depends(verify_token)):
    rid = new_request_id()
    try:
        settings.screenshots_dir.mkdir(parents=True, exist_ok=True)
        path = safe_child_path(settings.screenshots_dir, filename)
        if path.suffix.lower() not in {".png"}:
            path = path.with_suffix(".png")
        pyautogui.screenshot(str(path))
        audit_log(rid, "desktop_screenshot_file", {"path": str(path), "size": path.stat().st_size})
        return APIResponse(request_id=rid, success=True, data={"path": str(path), "size": path.stat().st_size})
    except Exception as e:
        audit_log(rid, "desktop_screenshot_file_failed", {"error": str(e)}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(**classify_exception(e)))


@router.post("/desktop/click", response_model=APIResponse)
def click(req: ClickRequest, _t: None = Depends(verify_token), _hr: None = Depends(verify_high_risk_token)):
    rid = new_request_id()
    try:
        width, height = pyautogui.size()
        if req.x >= width or req.y >= height:
            return APIResponse(request_id=rid, success=False, error=make_error(ErrorCode.INVALID_INPUT, "Click coordinates are outside the screen"))
        audit_log(rid, "desktop_click", {"x": req.x, "y": req.y, "button": req.button, "clicks": req.clicks})
        pyautogui.click(req.x, req.y, clicks=req.clicks, button=req.button)
        return APIResponse(request_id=rid, success=True, data={"clicked": f"{req.x},{req.y}"})
    except Exception as e:
        audit_log(rid, "desktop_click_failed", {"error": str(e)}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(**classify_exception(e)))


@router.post("/desktop/type", response_model=APIResponse)
def type_text(req: TypeRequest, _t: None = Depends(verify_token), _hr: None = Depends(verify_high_risk_token)):
    rid = new_request_id()
    try:
        audit_log(rid, "desktop_type", {"length": len(req.text), "interval": req.interval})
        pyautogui.typewrite(req.text, interval=req.interval)
        return APIResponse(request_id=rid, success=True, data={"typed": len(req.text)})
    except Exception as e:
        audit_log(rid, "desktop_type_failed", {"error": str(e)}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(**classify_exception(e)))


@router.post("/desktop/screen_size", response_model=APIResponse)
def screen_size(_: None = Depends(verify_token)):
    rid = new_request_id()
    w, h = pyautogui.size()
    return APIResponse(request_id=rid, success=True, data={"width": w, "height": h})


@router.post("/desktop/hotkey", response_model=APIResponse)
def hotkey(req: HotkeyRequest, _t: None = Depends(verify_token), _hr: None = Depends(verify_high_risk_token)):
    rid = new_request_id()
    try:
        keys = req.keys.split("+")
        audit_log(rid, "desktop_hotkey", {"keys": req.keys})
        pyautogui.hotkey(*keys)
        return APIResponse(request_id=rid, success=True, data={"hotkey": req.keys})
    except Exception as e:
        audit_log(rid, "desktop_hotkey_failed", {"error": str(e)}, status="error")
        return APIResponse(request_id=rid, success=False, error=make_error(**classify_exception(e)))
