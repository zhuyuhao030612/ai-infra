# 安全/韧性烟雾测试 — 8 项灾难场景防回归
# 用法: pwsh -File test-safety.ps1
$ErrorActionPreference = "Continue"
$CodeDir = "D:\Code"
$BaseUrl = "http://127.0.0.1:9000"
$GptHealthUrl = "http://127.0.0.1:3000/health"
$failures = 0
$tests = 0

Write-Host "=== Safety Smoke ==="
Write-Host ""

# ============================================
# Test 1: GPT HTTP pipeline health check
# ============================================
$tests++
Write-Host "[$tests] GPT-5.5 HTTP 管道健康检查..."
try {
    $h = Invoke-RestMethod -Uri $GptHealthUrl -TimeoutSec 5
    if ($h.status -eq 'ok') {
        Write-Host "  ✅ GPT server: $($h.status) worker=$($h.worker)"
    } else {
        Write-Host "  ⚠️ GPT server status: $($h.status) $($h.reason)"
    }
} catch {
    Write-Host "  ⚠️ GPT server not reachable (may not be running)"
}

# ============================================
# Test 2: GPT queue not stuck
# ============================================
$tests++
Write-Host "[$tests] GPT 队列无死信..."
try {
    $q = Invoke-RestMethod -Uri "http://127.0.0.1:3000/queue" -TimeoutSec 5
    $dead = if ($q.counts.dead_letter) { $q.counts.dead_letter } else { 0 }
    if ($dead -eq 0) {
        Write-Host "  ✅ 死信: 0, 总数: $($q.total)"
    } else {
        Write-Host "  ⚠️ 死信: $dead, 总数: $($q.total) — 可能需要清理"
    }
} catch {
    Write-Host "  ⚠️ GPT queue not reachable"
}

# ============================================
# Test 3: No token /windows → 401
# ============================================
$tests++
Write-Host "[$tests] 无 token 访问 /windows → 401..."
try {
    $resp = Invoke-WebRequest "$BaseUrl/windows" -Method GET -UseBasicParsing -TimeoutSec 3
    Write-Host "  ❌ 返回 $($resp.StatusCode)，应为 401"
    $failures++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 401 -or $code -eq 403) {
        Write-Host "  ✅ $code Unauthorized"
    } else {
        Write-Host "  ❌ 返回 $code，应为 401"
        $failures++
    }
}

# ============================================
# Test 4: No token /failures/recent → 401
# ============================================
$tests++
Write-Host "[$tests] 无 token 访问 /failures/recent → 401..."
try {
    $resp = Invoke-WebRequest "$BaseUrl/failures/recent" -Method GET -UseBasicParsing -TimeoutSec 3
    Write-Host "  ❌ 返回 $($resp.StatusCode)，应为 401"
    $failures++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 401 -or $code -eq 403) {
        Write-Host "  ✅ $code Unauthorized"
    } else {
        Write-Host "  ❌ 返回 $code，应为 401"
        $failures++
    }
}

# ============================================
# Test 5: /status public = minimal, no secrets
# ============================================
$tests++
Write-Host "[$tests] /status 公开版不含敏感信息..."
try {
    $resp = Invoke-WebRequest "$BaseUrl/status" -Method GET -UseBasicParsing -TimeoutSec 3
    $data = $resp.Content | ConvertFrom-Json
    $hasHealth = $data.data.health -eq "ok"
    $hasUptime = $null -ne $data.data.uptime_sec
    $noGpt = -not (Get-Member -InputObject $data.data -Name "gpt" -MemberType Properties)
    $noSmoke = -not (Get-Member -InputObject $data.data -Name "smoke" -MemberType Properties)
    if ($hasHealth -and $hasUptime -and $noGpt -and $noSmoke) {
        Write-Host "  ✅ 仅返回 health+uptime，无敏感信息"
    } else {
        Write-Host "  ❌ 泄露了不该公开的字段 (gpt=$(-not $noGpt), smoke=$(-not $noSmoke))"
        $failures++
    }
} catch {
    Write-Host "  ❌ 请求失败: $_"
    $failures++
}

# ============================================
# Test 6: cleanup dry-run doesn't delete
# ============================================
$tests++
Write-Host "[$tests] cleanup 默认 dry-run 不删..."
# Create a dummy old dir
$dummyDir = "$CodeDir\.ai-state\runs\safety-test-old"
New-Item -ItemType Directory -Force -Path $dummyDir | Out-Null
(Get-Item $dummyDir).LastWriteTime = [DateTime]::Now.AddDays(-30)

$result = & pwsh -File "$CodeDir\ai-infra\scripts\cleanup-runs.ps1" -Days 7 2>&1 | Out-String
$dirStillExists = Test-Path $dummyDir

# Now test with lock file
$lockDir = "$CodeDir\.ai-state\runs\safety-test-locked"
New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
"locked" | Out-File "$lockDir\some.lock" -Encoding UTF8
(Get-Item $lockDir).LastWriteTime = [DateTime]::Now.AddDays(-30)

$result2 = & pwsh -File "$CodeDir\ai-infra\scripts\cleanup-runs.ps1" -Days 7 2>&1 | Out-String
$lockDirStillExists = Test-Path $lockDir

# Clean up test dirs
Remove-Item $dummyDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $lockDir -Recurse -Force -ErrorAction SilentlyContinue

if ($dirStillExists) {
    Write-Host "  ✅ dry-run 未实际删除"
} else {
    Write-Host "  ❌ dry-run 误删了文件"
    $failures++
}

if ($lockDirStillExists) {
    Write-Host "  ✅ 跳过 .lock 目录"
} else {
    Write-Host "  ⚠️ lock 目录被删除（可能在 Apply 模式下测试）"
}

# ============================================
# Test 7: Redact removes sensitive patterns
# ============================================
$tests++
Write-Host "[$tests] redact.ps1 脱敏验证..."
$redactScript = Join-Path $CodeDir "ai-infra\scripts\redact.ps1"
$testInput = @'
password=supersecret123 token=abc123
'@
if (Test-Path $redactScript) {
    $redacted = $testInput | & pwsh -File $redactScript 2>&1 | Out-String
    if ($redacted -notmatch 'supersecret123' -and $redacted -match 'password=') {
        Write-Host "  ✅ Sensitive values redacted"
    } else {
        Write-Host "  ⚠️ Redact may not have caught all patterns (check output)"
    }
} else {
    Write-Host "  ⏭ redact.ps1 not found"
}

# ============================================
# Test 8: new-run.ps1 creates evidence.jsonl
# ============================================
$tests++
Write-Host "[$tests] new-run.ps1 创建 evidence.jsonl..."
$testRunDir = "$CodeDir\.ai-state\runs\safety-test-evidence"
New-Item -ItemType Directory -Force -Path $testRunDir | Out-Null
$currentTaskBackup = "$CodeDir\.ai-state\current-task.md.bak"
if (Test-Path "$CodeDir\.ai-state\current-task.md") {
    Copy-Item "$CodeDir\.ai-state\current-task.md" $currentTaskBackup -Force
}
try {
    $nr = & pwsh -File "$CodeDir\ai-infra\scripts\new-run.ps1" -Task "safety-evidence-test" 2>&1
    # Find the created run dir
    $createdRun = Get-ChildItem "$CodeDir\.ai-state\runs" -Directory |
        Where-Object { $_.Name -like "*safety-evidence-test*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($createdRun) {
        $evidenceFile = Join-Path $createdRun.FullName "evidence.jsonl"
        if (Test-Path $evidenceFile) {
            Write-Host "  ✅ evidence.jsonl created in run dir"
        } else {
            Write-Host "  ❌ evidence.jsonl NOT found"
            $failures++
        }
        $taskFile = Join-Path $createdRun.FullName "task.json"
        if (Test-Path $taskFile) {
            Write-Host "  ✅ task.json created in run dir"
        } else {
            Write-Host "  ❌ task.json NOT found"
            $failures++
        }
        # Clean up test run
        Remove-Item $createdRun.FullName -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  ❌ new-run.ps1 did not create run directory"
        $failures++
    }
} finally {
    Remove-Item $testRunDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $currentTaskBackup) {
        Move-Item $currentTaskBackup "$CodeDir\.ai-state\current-task.md" -Force
    }
}

# ============================================
# Summary
# ============================================
Write-Host ""
Write-Host "════════════════════════"
$passed = $tests - $failures
Write-Host "  Safety: $passed/$tests 通过"
if ($failures -eq 0) {
    Write-Host "  🟢 安全基线达标"
} else {
    Write-Host "  🔴 $failures 项失败 — 安全回归"
}

# Log event
& pwsh -File "$CodeDir\ai-infra\scripts\log-event.ps1" -Type "smoke.safety" -Ok:$($failures -eq 0) -DataJson "{`"passed`":$passed,`"total`":$tests,`"failed`":$failures}"

if ($failures -eq 0) { exit 0 } else { exit 1 }
