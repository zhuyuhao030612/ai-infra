# 实战数据记录 — 每个真实任务结束后调用
param([Parameter(Mandatory=$true)][string]$Task, [string]$Model="DeepSeek V4", [switch]$Success, [int]$TimeMin=0, [int]$Failures=0, [string]$BlockerUsed="", [switch]$HumanHelp, [string]$ToolsUsed="", [string]$LessonCreated="")

$logFile = "D:\Code\ai-infra\data\combat-log.jsonl"

$entry = [ordered]@{
    ts = (Get-Date -Format "yyyy-MM-dd HH:mm")
    task = $Task
    model = $Model
    success = $Success
    time_min = $TimeMin
    failures = $Failures
    blocker_used = $BlockerUsed
    human_help = $HumanHelp
    tools_used = $ToolsUsed
    lesson_created = $LessonCreated
} | ConvertTo-Json -Compress

Add-Content -Path $logFile -Value $entry -Encoding UTF8

# Quick stats
$all = Get-Content $logFile -EA SilentlyContinue | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} }
$total = ($all | Measure-Object).Count
$ok = ($all | Where-Object success).Count
Write-Host "Combat log: $ok/$total tasks successful"
Write-Host "Total entries: $total"
