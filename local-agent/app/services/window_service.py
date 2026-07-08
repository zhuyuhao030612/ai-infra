"""Window service — business logic, no HTTP dependency."""
from __future__ import annotations

import json
import shutil
import subprocess


def _powershell_exe() -> str:
    return shutil.which("pwsh") or shutil.which("powershell.exe") or "pwsh"


def get_windows() -> list[dict]:
    """Get all visible windows."""
    ps = r"""
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
Get-Process | Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle.Length -gt 0 } |
    Select-Object Id, ProcessName, MainWindowTitle |
    Sort-Object ProcessName |
    ConvertTo-Json -Compress
"""
    result = subprocess.run(
        [_powershell_exe(), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", ps],
        capture_output=True,
        text=True,
        timeout=10,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0 or not result.stdout.strip():
        return []
    data = json.loads(result.stdout)
    if isinstance(data, dict):
        data = [data]
    return [
        {"pid": w.get("Id"), "process": w.get("ProcessName", ""), "title": w.get("MainWindowTitle", "")}
        for w in data
    ]


def get_windows_by_process(process_name: str) -> list[dict]:
    return [w for w in get_windows() if w["process"].lower() == process_name.lower()]


def find_window(title_contains: str) -> dict | None:
    needle = title_contains.lower()
    for w in get_windows():
        if needle in w["title"].lower():
            return w
    return None
