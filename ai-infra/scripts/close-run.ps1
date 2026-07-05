# 任务结束收口器 — 检查 → 生成 report → 标记完成
# 用法: pwsh -File close-run.ps1 -Run "20260627-xxxx"
param(
    [Parameter(Mandatory=$true)][string]$Run,
    [string]$Outcome = "completed"  # completed | failed
)
$ErrorActionPreference = "Continue"

# AI Runtime guard
$guardModule = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib') 'AIRuntime.psm1'
if (Test-Path $guardModule) {
  Import-Module $guardModule -Force -ErrorAction SilentlyContinue
  if ($env:AI_ORCHESTRATED -ne '1') {
    Write-Warning "close-run.ps1 应通过 ai.ps1 调用。直接调用将在未来版本阻止。"
    Write-Warning "请使用: ai exec cap.task-lifecycle"
  }
}

# ── Preflight: verify run-state before closing ──
$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { "D:\Code" }
$statePath = Join-Path $projectDir ".claude\run-state\current.json"
if (Test-Path -LiteralPath $statePath) {
    try {
        $runState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $hasSkipTests = $false
        if ($runState.PSObject.Properties.Name -contains "waivers" -and $null -ne $runState.waivers) {
            $wJson = $runState.waivers | ConvertTo-Json -Depth 5 -Compress
            if ($wJson -match "skip-tests|skip_tests|skipTests") { $hasSkipTests = $true }
        }
        # Check tests_attempted (tests were run) rather than tests_run (which we set after verification below)
        $testsAttempted = if ($runState.PSObject.Properties.Name -contains "tests_attempted") { $runState.tests_attempted } else { $false }
        if (-not $testsAttempted -and -not $hasSkipTests) {
            Write-Host "BLOCKED: tests_attempted=false. Run tests before close-run."
            Write-Host "  Waiver: add 'skip-tests' to waivers in $statePath"
            exit 2
        }
        if ($runState.PSObject.Properties.Name -contains "close_run_done" -and $runState.close_run_done -eq $true -and -not $testsAttempted) {
            Write-Host "BLOCKED: close_run_done=true but tests not attempted (state inconsistent). Fix current.json first."
            exit 3
        }
    } catch {
        Write-Host "WARN: preflight read failed (fail-open): $($_.Exception.Message)"
    }
}

$CodeDir = "D:\Code"
$RunDir = "$CodeDir\.ai-state\runs\$Run"

if (-not (Test-Path $RunDir)) {
    Write-Host "Run directory not found: $RunDir"
    exit 1
}

Write-Host "=== Closing run: $Run ==="

# 1. Verify
Write-Host "[1/5] Verify..."
$verifyOk = $false
$result = & pwsh -File "$CodeDir\local-agent\scripts\verify.ps1" 2>&1
$verifyOk = ($LASTEXITCODE -eq 0)
if ($verifyOk) { Write-Host "  ✅ Pass" } else { Write-Host "  ❌ Fail" }
& pwsh -File "$CodeDir\ai-infra\scripts\run-log.ps1" -Run $Run -Step "verify" -Status $(if($verifyOk){'ok'}else{'fail'})

# 2. Smoke
Write-Host "[2/5] Smoke..."
$smokeOk = $false
$result = & pwsh -File "$CodeDir\ai-infra\smoke\run-all.ps1" 2>&1
$smokeOk = ($LASTEXITCODE -eq 0)
if ($smokeOk) { Write-Host "  ✅ Pass" } else { Write-Host "  ❌ Fail" }
& pwsh -File "$CodeDir\ai-infra\scripts\run-log.ps1" -Run $Run -Step "smoke" -Status $(if($smokeOk){'ok'}else{'fail'})

# 3. Safety (if 3+ files changed)
$changedCount = try { (git -C $CodeDir diff --name-only 2>$null | Measure-Object -Line).Lines } catch { 0 }
if ($changedCount -ge 3) {
    Write-Host "[3/5] Safety smoke ($changedCount files)..."
    $safetyOk = $false
    $result = & pwsh -File "$CodeDir\ai-infra\smoke\test-safety.ps1" 2>&1
    $safetyOk = ($LASTEXITCODE -eq 0)
    if ($safetyOk) { Write-Host "  ✅ Pass" } else { Write-Host "  ❌ Fail" }
    & pwsh -File "$CodeDir\ai-infra\scripts\run-log.ps1" -Run $Run -Step "safety" -Status $(if($safetyOk){'ok'}else{'fail'})
} else {
    Write-Host "[3/5] Safety smoke skipped (<3 files changed)"
}

# 4. Generate final-report
Write-Host "[4/5] Final report..."
$timelineFile = "$RunDir\timeline.jsonl"
$timeline = if (Test-Path $timelineFile) {
    (Get-Content $timelineFile | ForEach-Object {
        try { $_ | ConvertFrom-Json | ForEach-Object { "[$($_.ts)] $($_.step): $($_.status)" } } catch {}
    }) -join "`n"
} else { "(无时间线)" }

$gitDiff = try { git -C $CodeDir diff --stat 2>$null | Out-String } catch { "(非git)" }
$allOk = $verifyOk -and $smokeOk

$report = @"
# Final Report: $Run

**Closed**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Outcome**: $Outcome
**Status**: $(if($allOk){'🟢 全部通过'}else{'⚠️ 有问题'})

## Verification
- Verify: $(if($verifyOk){'✅'}else{'❌'})
- Smoke: $(if($smokeOk){'✅'}else{'❌'})

## Changed Files
$gitDiff

## Timeline
$timeline

## Risks
$(if($allOk){'无'}else{'请检查失败项'})

## Next
$(if($allOk){'任务完成，可以封版'}else{'修复失败项 → re-verify → 如涉 GPT 管道跑 safety smoke'})
"@
$report | Out-File "$RunDir\final-report.md" -Encoding UTF8
Write-Host "  ✅ $RunDir\final-report.md"

# 5. Update task.json and mark status
Write-Host "[5/5] Marking status & updating task.json..."

# Update README
$readme = "$RunDir\README.md"
if (Test-Path $readme) {
    $content = Get-Content $readme -Raw -Encoding UTF8
    $content = $content -replace '状态:.*', "状态: $Outcome"
    $content | Out-File $readme -Encoding UTF8
}

# Update task.json with result
$taskJsonPath = Join-Path $RunDir "task.json"
if (Test-Path $taskJsonPath) {
    try {
        $taskData = Get-Content $taskJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $newStatus = if ($allOk) { "completed" } else { "failed" }
        $taskData.status = $newStatus
        $existingTransitions = if ($taskData.transitions) { @($taskData.transitions) } else { @() }
        $existingTransitions += @{
            from = "running"
            to = $newStatus
            ts = (Get-Date -Format "o")
            reason = "Run closed: outcome=$Outcome verify=$verifyOk smoke=$smokeOk"
        }
        # Count evidence lines
        $evidencePath = Join-Path $RunDir "evidence.jsonl"
        $evidenceCount = if (Test-Path $evidencePath) {
            (Get-Content $evidencePath -Encoding UTF8 | Where-Object { $_ -notmatch '^#' -and $_.Trim() }).Count
        } else { 0 }
        $taskData.evidence_count = $evidenceCount
        $taskData.transitions = $existingTransitions
        $taskData.result = @{
            verify = $verifyOk
            smoke = $smokeOk
            outcome = $Outcome
            evidence_count = $evidenceCount
        }
        $taskData | ConvertTo-Json -Depth 6 | Out-File $taskJsonPath -Encoding UTF8
        Write-Host "  ✅ task.json updated: status=$newStatus evidence=$evidenceCount"
    } catch {
        Write-Host "  ⚠️ Failed to update task.json: $_"
    }
}

# Run state-transition
$stateResult = & pwsh -File "$CodeDir\ai-infra\scripts\state-transition.ps1" `
    -TaskId $Run -From "running" -To $(if($allOk){"completed"}else{"failed"}) `
    -Reason "Run closed: outcome=$Outcome" 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "  ✅ State transition recorded" }

# Suggest lesson if failed
if (-not $allOk) {
    Write-Host ""
    Write-Host "⚠️ 任务未完全通过 — 建议生成 lesson:"
    Write-Host "  pwsh -File $CodeDir\ai-infra\scripts\gen-lesson.ps1 -ErrorMessage '...' -Source '$Run'"
}

& pwsh -File "$CodeDir\ai-infra\scripts\run-log.ps1" -Run $Run -Step "close" -Status $(if($allOk){'ok'}else{'fail'}) -Note "outcome=$Outcome"
Write-Host ""
Write-Host "=== Run $Run closed: $Outcome ==="
exit $(if ($verifyOk -and $smokeOk) { 0 } else { 1 })

# ── Post-close: sync to Hook run-state ──
$hookProjectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { "D:\Code" }
$hookStatePath = Join-Path $hookProjectDir ".claude\run-state\current.json"
if (Test-Path -LiteralPath $hookStatePath) {
    try {
        $hookState = Get-Content -LiteralPath $hookStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $allPassed = ($verifyOk -and $smokeOk)
        $hookState.tests_run = $allPassed
        $hookState.close_run_done = $allPassed
        $hookState.close_run_attempted = $true
        $hookState.last_test_exit_code = if ($allPassed) { 0 } else { 1 }
        $hookState.closed_at = (Get-Date -Format 'o')
        if ($allPassed) { $hookState.evidence_collected = $true }
        # Use atomic write via Save-RunState if available
        $libPath = Join-Path $hookProjectDir ".claude\run-state\run-state.lib.ps1"
        if (Test-Path $libPath) {
            . $libPath
            if (Get-Command Save-RunState -ErrorAction SilentlyContinue) { Save-RunState -State $hookState } else { $hookState | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $hookStatePath -Encoding UTF8 }
        } else { $hookState | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $hookStatePath -Encoding UTF8 }
        Write-Host "  Hook state synced: tests_run=$($hookState.tests_run) close_run_done=$($hookState.close_run_done)"
    } catch {
        Write-Host "  WARN: Hook state sync failed (non-fatal): $($_.Exception.Message)"
    }
}

# ── A4: auto-write mem0 on close ──
try {
    $mem0Cli = "$env:USERPROFILE\.claude\projects\D--Code\memory\mem0_cli.py"
    if (Test-Path $mem0Cli) {
        $mem0Msg = if ($verifyOk -and $smokeOk) {
            "自动化闭环通过: run=$Run tests_run=true evidence_collected=true close_run_done=true。体系评级A-。"
        } else {
            "自动化闭环部分失败: run=$Run verify=$verifyOk smoke=$smokeOk。需检查失败项。"
        }
        $mem0Result = & uv run python $mem0Cli add $mem0Msg --category project_rule --tags automation,close-run 2>&1
        Write-Host "  mem0: $(if ($LASTEXITCODE -eq 0) { 'written' } else { 'skipped' })"
    }
} catch {
    Write-Host "  WARN: mem0 write failed (non-fatal): $($_.Exception.Message)"
}
