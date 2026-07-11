# AI Automation Worker — polls tasks, runs them, reports results
param([int]$PollIntervalSec=10, [switch]$Watchdog)
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"
$inbox = "D:\Code\ai-infra\tasks\inbox"
$processing = "D:\Code\ai-infra\tasks\processing"
New-Item -ItemType Directory -Force -Path $inbox,$processing | Out-Null

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Automation worker started. Watching $inbox"

while ($true) {
  # Ensure services
  if ($Watchdog) { & "D:\Code\ai-infra\automation\ensure-services.ps1" -SkipWatchdog }

  # Pick up oldest task
  $tasks = Get-ChildItem $inbox -Filter "*.task.json" -ErrorAction SilentlyContinue | Sort-Object Name
  if ($tasks.Count -gt 0) {
    $taskFile = $tasks[0]
    $procFile = Join-Path $processing $taskFile.Name

    # Atomic claim
    try {
      Move-Item $taskFile.FullName $procFile -Force -ErrorAction Stop
    } catch { Start-Sleep -Seconds $PollIntervalSec; continue }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Processing: $($taskFile.Name)"

    # Check L3+ and block if needed
    $task = Get-Content $procFile -Raw | ConvertFrom-Json
    if ($task.max_level -in @("L3","L4","L5") -and -not $task.allow_l3) {
      Move-Item $procFile "D:\Code\ai-infra\tasks\blocked\$($taskFile.Name)" -Force
      @{id=$task.id;reason="L3+ blocked in unattended mode";ts=(Get-Date -Format "o")} | ConvertTo-Json | Out-File "D:\Code\ai-infra\tasks\blocked\$($task.id).blocked.json" -Encoding UTF8
      Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Blocked (L3+): $($task.id)"
      Start-Sleep -Seconds $PollIntervalSec
      continue
    }

    # Run task
    $env:AI_RUN_ID = $task.id
    $result = & pwsh -NoLogo -NoProfile -File "D:\Code\ai-infra\automation\run-task.ps1" -TaskFile $procFile 2>&1
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Result: $result"

    # Clean processing
    Remove-Item $procFile -Force -ErrorAction SilentlyContinue
  }

  Start-Sleep -Seconds $PollIntervalSec
}
