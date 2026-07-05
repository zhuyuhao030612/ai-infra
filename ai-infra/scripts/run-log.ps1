# 记录任务时间线事件
# 用法: pwsh -File run-log.ps1 -Run "20260627-xxxx" -Step "impact" -Status "ok" -Note "3 files affected"
param(
    [Parameter(Mandatory=$true)][string]$Run,
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][string]$Status,  # ok | fail | skip
    [string]$Note = ""
)
$ErrorActionPreference = "Continue"
$RunsDir = "D:\Code\.ai-state\runs"
$timelineFile = "$RunsDir\$Run\timeline.jsonl"

New-Item -ItemType Directory -Force -Path (Split-Path $timelineFile -Parent) | Out-Null

$entry = [ordered]@{
    ts = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    step = $Step
    status = $Status
    note = $Note
} | ConvertTo-Json -Compress
Add-Content -Path $timelineFile -Value $entry -Encoding UTF8
