# local-agent start script — called by watchdog or manually
param([ValidateRange(1,65535)][int]$Port=9000,[ValidateSet('127.0.0.1','localhost')][string]$HostAddr='127.0.0.1')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ScriptDir=Split-Path -Parent $PSCommandPath
$ProjectDir=(Resolve-Path -LiteralPath (Join-Path $ScriptDir '..')).Path
$Python=Join-Path $ProjectDir '.venv\Scripts\python.exe'
if(!(Test-Path $Python)){Write-Host "[start] .venv not found at $Python — run 'uv sync' first"; exit 1}
if(!(Test-Path (Join-Path $ProjectDir 'app'))){Write-Host '[start] app directory not found'; exit 1}
Write-Host "[start] Launching local-agent on ${HostAddr}:${Port}..."
$env:PYTHONUNBUFFERED='1'
Push-Location $ProjectDir
try{& $Python -m uvicorn app.main:app --host $HostAddr --port $Port --log-level warning; exit $(if($null -ne $LASTEXITCODE){$LASTEXITCODE}else{0})}finally{Pop-Location}
