# 一屏总诊断 — 接管系统时立刻知道能不能干活
$ErrorActionPreference = "Continue"
$CodeDir = "D:\Code"

Write-Host "╔══════════════════════════════════════════╗"
Write-Host "║       AI Doctor — 系统总诊断             ║"
Write-Host "╚══════════════════════════════════════════╝"
Write-Host ""

$checks = @()

# 1. local-agent
try {
    $health = Invoke-RestMethod "http://127.0.0.1:9000/health" -TimeoutSec 3
    $checks += @{name="local-agent"; ok=$true; detail="online"}
} catch { $checks += @{name="local-agent"; ok=$false; detail="OFFLINE"} }

# 2. GPT queue
$inbox = (Get-ChildItem "$CodeDir\ai-pipeline\gpt-queue\inbox\*.json" -EA SilentlyContinue).Count
$proc = (Get-ChildItem "$CodeDir\ai-pipeline\gpt-queue\processing\*.json" -EA SilentlyContinue).Count
$failedQ = (Get-ChildItem "$CodeDir\ai-pipeline\gpt-queue\failed" -Directory -EA SilentlyContinue).Count
$gptLog = "$CodeDir\ai-pipeline\gpt55-output.log"
$gptOk = (Test-Path $gptLog) -and ((Get-Content $gptLog -Tail 10) -match '\[ready\]')
$checks += @{name="GPT queue"; ok=($inbox+$proc -lt 3); detail="inbox=$inbox proc=$proc failed=$failedQ online=$gptOk"}

# 3. Smoke
$smokeHistory = "$CodeDir\ai-infra\smoke\smoke-history.jsonl"
$lastSmoke = if (Test-Path $smokeHistory) {
    try { (Get-Content $smokeHistory -Tail 1 | ConvertFrom-Json) } catch { $null }
} else { $null }
$smokeAge = if ($lastSmoke) { [Math]::Round(([DateTime]::Now - [DateTime]$lastSmoke.timestamp).TotalHours, 1) } else { 999 }
$checks += @{name="smoke"; ok=($smokeAge -lt 24); detail="$(if($lastSmoke){"$($lastSmoke.passed)/$($lastSmoke.total) ${smokeAge}h ago"}else{'never'})"}

# 4. Events log
$eventsLog = "$CodeDir\ai-infra\logs\events.jsonl"
$eventsSize = if (Test-Path $eventsLog) { [Math]::Round((Get-Item $eventsLog).Length / 1MB, 1) } else { 0 }
$checks += @{name="events"; ok=($eventsSize -lt 50); detail="${eventsSize}MB"}

# 5. Failures
$failCount = (Get-ChildItem "$CodeDir\ai-infra\failures" -Directory -EA SilentlyContinue).Count
$checks += @{name="failures"; ok=($failCount -lt 10); detail="$failCount artifacts"}

# 6. Lessons
$lessonDir = "$CodeDir\ai-infra\data\lessons"
$drafts = (Get-ChildItem "$lessonDir\L*-*.md" -EA SilentlyContinue | Where-Object {
    (Get-Content $_.FullName -Raw -EA SilentlyContinue) -match 'status:\s*draft'
}).Count
$checks += @{name="lessons"; ok=($drafts -lt 5); detail="drafts=$drafts"}

# 7. Watchdog
$wdLog = "$CodeDir\local-agent\logs\watchdog.log"
$restarts = if (Test-Path $wdLog) { ([regex]::Matches((Get-Content $wdLog -Raw), "RESTART #")).Count } else { 0 }
$checks += @{name="watchdog"; ok=($restarts -lt 10); detail="$restarts restarts"}

# Render
$allOk = $true
foreach ($c in $checks) {
    $icon = if ($c.ok) { "✅" } else { "❌" }
    if (-not $c.ok) { $allOk = $false }
    Write-Host "  $icon $($c.name): $($c.detail)"
}

# Recommended action
Write-Host ""
Write-Host "── 建议下一步 ──"
$actions = @()
if (-not $allOk) {
    if (-not ($checks | Where-Object name -eq "local-agent").ok) { $actions += "启动 local-agent 或检查 watchdog" }
    if (-not ($checks | Where-Object name -eq "GPT queue").ok) { $actions += "检查 GPT queue: inbox/proc/failed 状态" }
}
if ($smokeAge -gt 24) { $actions += "超过 24h 未 smoke，建议 pwsh smoke/run-all.ps1" }
if ($failedQ -gt 0) { $actions += "有 $failedQ 个 GPT 失败请求，建议 explain-failure.ps1" }
if ($drafts -gt 0) { $actions += "$drafts 条 draft lessons 待确认" }
if ($eventsSize -gt 50) { $actions += "events.jsonl > 50MB，建议 cleanup" }
if ($failCount -gt 10) { $actions += "失败证据包 > 10，建议 cleanup 或复盘" }

if ($actions.Count -eq 0) {
    Write-Host "  🟢 系统健康，可以干活"
} else {
    foreach ($a in $actions) { Write-Host "  → $a" }
}

Write-Host ""
# Health Score
$score = 100
if ($failedQ -gt 0) { $score -= 10 * $failedQ }
if ($smokeAge -gt 24) { $score -= 10 }
if ($drafts -gt 5) { $score -= 5 }
if ($eventsSize -gt 50) { $score -= 5 }
if ($proc -gt 0) { $score -= 20 }
if ($restarts -gt 3) { $score -= 15 }
if (-not ($checks | Where-Object name -eq "local-agent").ok) { $score -= 30 }

$scoreIcon = if ($score -ge 90) { "🟢" } elseif ($score -ge 70) { "🟡" } else { "🔴" }
Write-Host ""
Write-Host "  Health Score: $scoreIcon $score/100"

if ($allOk) { Write-Host "  状态: 🟢 就绪" } else { Write-Host "  状态: ⚠️ 需要关注" }
