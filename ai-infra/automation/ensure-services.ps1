# Ensure all services are alive
param([switch]$SkipWatchdog)
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"
$results = @{}

# local-agent
try {
  $r = Invoke-WebRequest -Uri "http://127.0.0.1:9000/health" -UseBasicParsing -TimeoutSec 3
  $results.local_agent = ($r.StatusCode -eq 200)
} catch { $results.local_agent = $false }

# gpt55-server
try {
  $h = Invoke-RestMethod -Uri "http://127.0.0.1:3000/health" -TimeoutSec 3
  $results.gpt55_server = ($h.busy -eq $false)
} catch { $results.gpt55_server = $false }

if (-not $SkipWatchdog -and -not $results.gpt55_server) {
  Write-Host "gpt55-server appears down, run: start D:\Code\ai-pipeline\start-gpt55.bat"
}

$results.ts = (Get-Date -Format "o")
$results | ConvertTo-Json | Out-File "D:\Code\ai-infra\runtime\service-status.json" -Encoding UTF8
return $results
