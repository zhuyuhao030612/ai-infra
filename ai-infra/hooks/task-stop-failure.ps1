# Task stop-failure hook — mark failed, trigger analysis
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failDir = "D:\Code\ai-infra\tasks\failed"
$ts = Get-Date -Format "o"
$runId = $env:AI_RUN_ID ?? (Get-Date -Format "yyyyMMdd-HHmmss")
$fdir = Join-Path $failDir $runId
New-Item -ItemType Directory -Force -Path $fdir | Out-Null
@{
  event = "StopFailure"
  ts = $ts
  runId = $runId
} | ConvertTo-Json | Out-File (Join-Path $fdir "stop-failure.json") -Encoding UTF8
