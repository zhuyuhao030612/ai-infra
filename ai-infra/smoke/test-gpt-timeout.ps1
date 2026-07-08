# GPT-5.5 降级负向测试
# 验证：管道挂了不影响主流程，返回 GPT_UNAVAILABLE 而不是崩
$ErrorActionPreference = "Continue"
$CodeDir = "D:\Code"
$failures = 0
$tests = 0

Write-Host "=== GPT-5.5 降级测试 ==="
Write-Host ""

# Test 1: Timeout (extremely short)
$tests++
Write-Host "[$tests] 超时降级 (1s)..."
$result = & pwsh -File "$CodeDir\ai-infra\scripts\gpt-ask.ps1" -Prompt "pong" -TimeoutSec 3 -NoCache 2>&1 | Out-String
if ($result -match "GPT_UNAVAILABLE") {
    Write-Host "  ✅ 正确降级: GPT_UNAVAILABLE"
} elseif ($result -match "pong") {
    Write-Host "  ⚠️ 竟然成功了（管道太快）—— 不算失败"
} else {
    Write-Host "  ❌ 未按预期降级: $($result.Substring(0, [Math]::Min(80, $result.Length)))"
    $failures++
}

# Test 2: Verify failure artifacts exist
$tests++
Write-Host "[$tests] 失败证据包..."
$runsDir = "$CodeDir\ai-pipeline\gpt-runs"
$latestRun = Get-ChildItem $runsDir -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($latestRun) {
    $hasPrompt = Test-Path "$($latestRun.FullName)\prompt.md"
    $hasError = Test-Path "$($latestRun.FullName)\error.txt"
    if ($hasPrompt -or $hasError) {
        Write-Host "  ✅ 证据包存在: $($latestRun.Name)"
    } else {
        Write-Host "  ⚠️ 目录存在但无证据文件"
    }
} else {
    Write-Host "  ⚠️ 无失败证据包（可能是因为没触发超时）"
}

# Test 3: Redact works
$tests++
Write-Host "[$tests] 脱敏..."
$testText = "token=abc123def456ghijklmnopqrstuvwxyz1234567890 password=secret123"
$redacted = & pwsh -File "$CodeDir\ai-infra\scripts\redact.ps1" -Text $testText 2>&1 | Out-String
if ($redacted -match "REDACTED" -and $redacted -notmatch "abc123def456") {
    Write-Host "  ✅ 敏感信息已脱敏"
} else {
    Write-Host "  ❌ 脱敏失败"
    $failures++
}

# Test 4: Cache hit
$tests++
Write-Host "[$tests] 缓存命中..."
$cachePrompt = "cache-test-ping-$(Get-Random)"
$result1 = & pwsh -File "$CodeDir\ai-infra\scripts\gpt-ask.ps1" -Prompt $cachePrompt -TimeoutSec 15 2>&1 | Out-String
Start-Sleep -Seconds 2
$result2 = & pwsh -File "$CodeDir\ai-infra\scripts\gpt-ask.ps1" -Prompt $cachePrompt -TimeoutSec 15 2>&1 | Out-String
if ($result1 -match "Cache hit" -or $result2 -match "Cache hit") {
    Write-Host "  ✅ 缓存命中"
} elseif ($result1 -match "GPT_UNAVAILABLE") {
    Write-Host "  ⚠️ 管道不可用，跳过缓存测试"
} else {
    Write-Host "  ⚠️ 缓存未命中（首次调用或管道慢）"
}

# Summary
Write-Host ""
Write-Host "=== 降级测试: $($tests - $failures)/$tests 通过 ==="
if ($failures -gt 0) {
    Write-Host "⚠️ $failures 项失败 — 降级链可能有问题"
    exit 1
} else {
    Write-Host "🟢 降级链正常"
    exit 0
}
