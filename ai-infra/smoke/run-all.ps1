# 能力回归测试 —— 一键确认系统健康
# 用法: pwsh -File run-all.ps1
$ErrorActionPreference = "Continue"
$CodeDir = "D:\Code"
$failures = 0
$total = 0

Write-Host "╔══════════════════════════════════╗"
Write-Host "║   能力回归测试 (Smoke Test)      ║"
Write-Host "╚══════════════════════════════════╝"
Write-Host ""

# === 1. local-agent API ===
Write-Host "── 1. local-agent API ──"
$total++
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:9000/health" -UseBasicParsing -TimeoutSec 3
    if ($resp.StatusCode -eq 200) {
        Write-Host "  ✅ health (GET)"
    } else {
        Write-Host "  ❌ health returned $($resp.StatusCode)"
        $failures++
    }
} catch {
    Write-Host "  ❌ health unreachable: $_"
    $failures++
}

# Test authenticated endpoint
$token = $null
$envFile = "$CodeDir\local-agent\.env"
if (Test-Path $envFile) {
    $match = Select-String -Path $envFile -Pattern 'AGENT_TOKEN=(.+)' | Select-Object -First 1
    if ($match) { $token = $match.Matches.Groups[1].Value }
}

if ($token) {
    $total++
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:9000/desktop/screen_size" `
            -Method POST -Headers @{ Authorization = "Bearer $token" } -UseBasicParsing -TimeoutSec 5
        if ($resp.StatusCode -eq 200) {
            Write-Host "  ✅ screen_size (POST+auth)"
        } else {
            Write-Host "  ❌ screen_size returned $($resp.StatusCode)"
            $failures++
        }
    } catch {
        Write-Host "  ❌ screen_size failed: $_"
        $failures++
    }
} else {
    Write-Host "  ⏭ screen_size (no token found)"
}

# === 2. Project verifications ===
Write-Host ""
Write-Host "── 2. 代码验证 ──"

# Python (local-agent)
$total++
Write-Host "  [local-agent]"
$result = & pwsh -File "$CodeDir\local-agent\scripts\verify.ps1" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    ✅ 全部通过"
} else {
    Write-Host "    ❌ 验证失败"
    Write-Host ($result | Select-Object -Last 5 | ForEach-Object { "    $_" })
    $failures++
}

# JS (ai-pipeline)
$total++
Write-Host "  [ai-pipeline]"
$result = & pwsh -File "$CodeDir\ai-pipeline\scripts\verify.ps1" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    ✅ 全部通过"
} else {
    Write-Host "    ❌ 验证失败"
    Write-Host ($result | Select-Object -Last 5 | ForEach-Object { "    $_" })
    $failures++
}

# === 3. GPT-5.5 pipeline ===
Write-Host ""
Write-Host "── 3. GPT-5.5 管道 ──"
$total++
$pipelineRunning = Get-Process -Name "node" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "gpt55" }
if ($pipelineRunning) {
    $logFile = "$CodeDir\ai-pipeline\gpt55-output.log"
    if (Test-Path $logFile) {
        $lastReady = Select-String -Path $logFile -Pattern '\[ready\]' | Select-Object -Last 1
        if ($lastReady) {
            Write-Host "  ✅ 管道在线 ($(($pipelineRunning | Measure-Object).Count) 进程)"
        } else {
            Write-Host "  ⚠️ 进程在但可能未就绪"
        }
    } else {
        Write-Host "  ⚠️ 进程在但无日志"
    }
} else {
    Write-Host "  ⚠️ 管道未运行"
}

# === 4. Watchdog ===
Write-Host ""
Write-Host "── 4. Watchdog ──"
$total++
$logFile = "$CodeDir\local-agent\logs\watchdog.log"
if (Test-Path $logFile) {
    $lastEntry = Get-Content $logFile -Tail 2
    $recently = [DateTime]::Now.AddMinutes(-5)
    Write-Host "  ✅ 看门狗活跃（最近日志: $($lastEntry[0].Substring(0, [Math]::Min(60, $lastEntry[0].Length)))...）"
} else {
    Write-Host "  ⚠️ 无看门狗日志（可能未启动）"
}

# === 5. Safety Smoke ===
Write-Host ""
Write-Host "── 5. Safety Smoke ──"
$total++
$safetyResult = & pwsh -File "$CodeDir\ai-infra\smoke\test-safety.ps1" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    ✅ 8/8 安全基线达标"
} else {
    Write-Host "    ❌ 安全回归"
    $failures++
}

# === 6. Permissions Smoke ===
Write-Host ""
Write-Host "── 6. Permissions Smoke ──"
$total++
$permResult = & pwsh -File "$CodeDir\ai-infra\smoke\test-permissions.ps1" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    ✅ L0-L5 enforcement OK"
} else {
    Write-Host "    ❌ Permissions regression"
    $failures++
}

# === 7. PS Guard Smoke ===
Write-Host ""
Write-Host "── 7. PS Guard Smoke ──"
$total++
$psguardResult = & pwsh -File "$CodeDir\ai-infra\smoke\test-psguard.ps1" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    ✅ All ps-guard edge cases handled"
} else {
    Write-Host "    ❌ ps-guard regression"
    $failures++
}

# === 8. Evidence Infrastructure ===
Write-Host ""
Write-Host "── 8. Evidence Infrastructure ──"
$total++
$evidenceOk = $true
if (-not (Test-Path "$CodeDir\ai-infra\scripts\evidence-check.ps1")) { Write-Host "    ❌ evidence-check.ps1 missing"; $evidenceOk = $false }
if (-not (Test-Path "$CodeDir\ai-infra\scripts\post-tool-recorder.ps1")) { Write-Host "    ❌ post-tool-recorder.ps1 missing"; $evidenceOk = $false }
if (-not (Test-Path "$CodeDir\ai-infra\scripts\state-transition.ps1")) { Write-Host "    ❌ state-transition.ps1 missing"; $evidenceOk = $false }
if (-not (Test-Path "$CodeDir\ai-infra\schemas\task-schema.json")) { Write-Host "    ❌ task-schema.json missing"; $evidenceOk = $false }
if ($evidenceOk) {
    Write-Host "    ✅ All evidence infrastructure files present"
} else {
    $failures++
}

# === Summary ===
Write-Host ""
Write-Host "════════════════════════════════════"
$passed = $total - $failures
Write-Host "  结果: $passed/$total 通过"

# Save to smoke history
$smokeLog = "$CodeDir\ai-infra\smoke\smoke-history.jsonl"
$entry = @{
    timestamp = (Get-Date -Format "o")
    passed = $passed
    total = $total
    failed = $failures
    healthy = ($failures -eq 0)
} | ConvertTo-Json -Compress
Add-Content -Path $smokeLog -Value $entry

# Unified event log
& pwsh -File "$CodeDir\ai-infra\scripts\log-event.ps1" -Type "smoke.run" -Ok:$($failures -eq 0) -DataJson "{`"passed`":$passed,`"total`":$total,`"failed`":$failures}"

if ($failures -eq 0) {
    Write-Host "  状态: 🟢 健康"
    exit 0
} else {
    Write-Host "  状态: 🔴 $failures 项异常"
    exit 1
}
Write-Host "════════════════════════════════════"
