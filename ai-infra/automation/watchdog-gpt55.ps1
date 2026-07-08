# GPT-5.5 Watchdog — monitors health, auto-restarts on failure
param(
  [int]$IntervalSec = 30,
  [int]$MaxRestartsPerHour = 10,
  [switch]$Once
)

$ErrorActionPreference = "Continue"
$logDir = "D:\Code\ai-infra\runtime"
$logFile = Join-Path $logDir "watchdog-gpt55.log"
$stateFile = Join-Path $logDir "watchdog-gpt55-state.json"
$envFile = "D:\Code\ai-pipeline\.env.ps1"
$serverDir = "D:\Code\ai-pipeline"
$healthUrl = "http://127.0.0.1:3000/health"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force $logDir | Out-Null }

function Write-Log($msg) {
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  "$ts | $msg" | Out-File $logFile -Append -Encoding UTF8
  Write-Host "$ts | $msg"
}

function Get-State {
  if (Test-Path $stateFile) {
    try { return Get-Content $stateFile -Raw | ConvertFrom-Json } catch { }
  }
  return @{ restarts = @(); totalRestarts = 0 }
}

function Save-State($s) {
  $s | ConvertTo-Json -Depth 3 | Set-Content $stateFile -Encoding UTF8
}

function Test-GPT55 {
  try {
    $r = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5
    return ($r -and $r.busy -eq $false)
  } catch { return $false }
}

function Restart-GPT55 {
  Write-Log "RESTART: killing stale node processes..."
  Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3

  Write-Log "RESTART: loading env and starting server..."
  if (Test-Path $envFile) { . $envFile }

  $proc = Start-Process node -ArgumentList "gpt55-server.js" `
    -WorkingDirectory $serverDir `
    -NoNewWindow `
    -RedirectStandardOutput "$logDir\gpt55-stdout.log" `
    -RedirectStandardError "$logDir\gpt55-stderr.log" `
    -PassThru

  Start-Sleep -Seconds 5
  $alive = Test-GPT55
  Write-Log "RESTART: server PID=$($proc.Id), health=$alive"
  return $alive
}

# === Main ===
Write-Log "WATCHDOG START interval=${IntervalSec}s maxRestarts=${MaxRestartsPerHour}/h"

do {
  $alive = Test-GPT55

  if (-not $alive) {
    Write-Log "DOWN: GPT-5.5 not responding"

    $state = Get-State
    $recentRestarts = @($state.restarts | Where-Object {
      [datetime]$_ -gt (Get-Date).AddHours(-1)
    })

    if ($recentRestarts.Count -ge $MaxRestartsPerHour) {
      Write-Log "THROTTLE: $MaxRestartsPerHour restarts in 1h, skipping auto-restart"
    } else {
      $ok = Restart-GPT55
      if ($ok) {
        $state.restarts = @($recentRestarts) + (Get-Date -Format "o")
        $state.totalRestarts++
        Save-State $state
      } else {
        Write-Log "FAIL: restart did not bring server back"
      }
    }
  }

  if (-not $Once) { Start-Sleep -Seconds $IntervalSec }
} until ($Once)
