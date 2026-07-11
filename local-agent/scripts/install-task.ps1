# Install local-agent watchdog as Windows scheduled task
# Runs at user logon, keeps local-agent alive
# Usage: pwsh -File install-task.ps1
param(
    [int]$Port = 9000
)

$ErrorActionPreference = "Stop"
$TaskName = "LocalAgentWatchdog"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WatchdogScript = Join-Path $ScriptDir "watchdog.ps1"

if (-not (Test-Path $WatchdogScript)) {
    Write-Host "[ERROR] watchdog.ps1 not found at $WatchdogScript"
    exit 1
}

# Remove old task if exists
schtasks /delete /tn $TaskName /f 2>$null
Write-Host "Removed old task (if any)"

# Create new task: run at user logon, hidden window, restart every minute if killed
$action = "pwsh -NoLogo -WindowStyle Hidden -File `"$WatchdogScript`" -Port $Port"
schtasks /create `
  /tn $TaskName `
  /tr "$action" `
  /sc onlogon `
  /rl HIGHEST `
  /f

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to create scheduled task"
    exit 1
}

Write-Host "[OK] Task '$TaskName' created — watchdog starts at logon"

# Start it now
schtasks /run /tn $TaskName
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Watchdog started"
} else {
    Write-Host "[WARN] Task created but couldn't start. It will run at next logon."
}

Write-Host ""
Write-Host "Check status: schtasks /query /tn $TaskName"
Write-Host "Check logs:   D:\Code\local-agent\logs\watchdog.log"
Write-Host "Stop:         schtasks /end /tn $TaskName"
Write-Host "Uninstall:    schtasks /delete /tn $TaskName /f"
