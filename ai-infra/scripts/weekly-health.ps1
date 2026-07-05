# 每周健康报告 — 一页概览
# 用法: pwsh -File weekly-health.ps1
$ErrorActionPreference = "Continue"
$CodeDir = "D:\Code"
$now = Get-Date

Write-Host "╔══════════════════════════════════╗"
Write-Host "║   每周健康报告 — $($now.ToString('yyyy-MM-dd'))       ║"
Write-Host "╚══════════════════════════════════╝"
Write-Host ""

# === 1. local-agent ===
Write-Host "── 1. local-agent ──"
try {
    $health = Invoke-RestMethod "http://127.0.0.1:9000/health" -TimeoutSec 3
    Write-Host "  健康: $($health.data.status)"
} catch { Write-Host "  ❌ 不可达" }

try {
    $status = Invoke-RestMethod "http://127.0.0.1:9000/status" -TimeoutSec 3
    Write-Host "  Uptime: $($status.data.uptime)"
} catch {}

# Check watchdog
$wdLog = "$CodeDir\local-agent\logs\watchdog.log"
if (Test-Path $wdLog) {
    $restarts = (Get-Content $wdLog -Raw | Select-String "RESTART #" -AllMatches).Matches.Count
    Write-Host "  Watchdog 重启: $restarts 次"
}

# === 2. GPT Pipeline ===
Write-Host ""
Write-Host "── 2. GPT-5.5 管道 ──"
$gptLog = "$CodeDir\ai-pipeline\gpt55-output.log"
if (Test-Path $gptLog) {
    $lastReady = (Get-Content $gptLog -Tail 20 | Select-String "\[ready\]" | Select-Object -Last 1)
    $lastError = (Get-Content $gptLog -Tail 20 | Select-String "\[error\]" | Select-Object -Last 1)
    if ($lastReady) { Write-Host "  状态: 在线" } else { Write-Host "  状态: ⚠️ 可能离线" }
    if ($lastError) { Write-Host "  最近错误: $($lastError.Line.Substring(0,[Math]::Min(80,$lastError.Line.Length)))" }
}

# Queue stats
$inbox = (Get-ChildItem "$CodeDir\ai-pipeline\gpt-queue\inbox\*.json" -ErrorAction SilentlyContinue).Count
$processing = (Get-ChildItem "$CodeDir\ai-pipeline\gpt-queue\processing\*.json" -ErrorAction SilentlyContinue).Count
$failedQ = (Get-ChildItem "$CodeDir\ai-pipeline\gpt-queue\failed" -Directory -ErrorAction SilentlyContinue).Count
Write-Host "  队列: inbox=$inbox processing=$processing failed=$failedQ"

# === 3. Events ===
Write-Host ""
Write-Host "── 3. 事件日志 ──"
$eventsLog = "$CodeDir\ai-infra\logs\events.jsonl"
if (Test-Path $eventsLog) {
    $sizeMB = [Math]::Round((Get-Item $eventsLog).Length / 1MB, 1)
    $lineCount = (Get-Content $eventsLog | Measure-Object -Line).Lines
    Write-Host "  大小: ${sizeMB}MB / $lineCount 行"
    if ($sizeMB -gt 50) { Write-Host "  ⚠️ 建议按日期切分" }
}

# === 4. Failures ===
Write-Host ""
Write-Host "── 4. 失败证据包 ──"
$failDir = "$CodeDir\ai-infra\failures"
if (Test-Path $failDir) {
    $failCount = (Get-ChildItem $failDir -Directory -ErrorAction SilentlyContinue).Count
    Write-Host "  总数: $failCount"
    # Latest 3
    $latest = Get-ChildItem $failDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 3
    foreach ($f in $latest) {
        $manifest = "$($f.FullName)\manifest.json"
        $summary = if (Test-Path $manifest) {
            try { (Get-Content $manifest -Raw | ConvertFrom-Json).summary } catch { "?" }
        } else { "无 manifest" }
        Write-Host "    $($f.Name): $summary"
    }
}

# === 5. Lessons ===
Write-Host ""
Write-Host "── 5. 经验库 ──"
$lessonsDir = "$CodeDir\ai-infra\data\lessons"
$drafts = (Get-ChildItem "$lessonsDir\L*-*.md" -ErrorAction SilentlyContinue | Where-Object {
    (Get-Content $_.FullName -Raw) -match 'status:\s*draft'
}).Count
$finals = (Get-ChildItem "$lessonsDir\L*-*.md" -ErrorAction SilentlyContinue | Where-Object {
    (Get-Content $_.FullName -Raw) -match 'status:\s*final'
}).Count
$totalL = (Get-ChildItem "$lessonsDir\L*-*.md" -ErrorAction SilentlyContinue).Count
Write-Host "  Total: $totalL (draft=$drafts, final=$finals)"

# === 6. Cleanup Preview ===
Write-Host ""
Write-Host "── 6. 可清理空间预览 ──"
$result = & pwsh -File "$CodeDir\ai-infra\scripts\cleanup-runs.ps1" -Days 30 2>&1 | Select-String "清理|将清理|DRY|总计"
$result | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "════════════════════════════════════"
Write-Host "  报告生成: $($now.ToString('yyyy-MM-dd HH:mm'))"

# Log event
& pwsh -File "$CodeDir\ai-infra\scripts\log-event.ps1" -Type "weekly.health" -Ok:$true -DataJson "{`"date`":`"$($now.ToString('yyyy-MM-dd'))`"}"
