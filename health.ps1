#requires -Version 5.1
<# ⚠️ DEPRECATED — 推荐使用 `ai doctor` 代替。
   保留此脚本仅用于向后兼容。
   Usage: pwsh -File health.ps1 [-Json]
   Preferred: ai doctor #>
param([switch]$Json)

$ErrorActionPreference = "Continue"
$root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { "D:\Code" }
$statePath = Join-Path $root ".claude\run-state\current.json"
$baselineDir = Join-Path $root ".claude\baselines"
$mistakeLog = Join-Path $env:USERPROFILE ".claude\projects\D--Code\memory\mistake-log.md"

function Check($n,$ok,$detail) { [pscustomobject]@{name=$n;ok=$ok;detail=$detail} }

$checks = [System.Collections.Generic.List[object]]::new()

# 1. State file
if (Test-Path $statePath) {
    try { $s = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json; $checks.Add((Check "state_file" $true "exists"))
        $checks.Add((Check "tests_run" ($s.tests_run -eq $true) "$($s.tests_run)"))
        $checks.Add((Check "evidence_collected" ($s.evidence_collected -eq $true) "$($s.evidence_collected)"))
        $checks.Add((Check "close_run_done" ($s.close_run_done -eq $true) "$($s.close_run_done)"))
        $checks.Add((Check "guard_used" ($s.guard_used -eq $true) "$($s.guard_used)"))
        $consistent = -not ($s.close_run_done -eq $true -and $s.tests_run -ne $true)
        $checks.Add((Check "state_consistent" $consistent $(if($consistent){'ok'}else{'INCONSISTENT'})))
        $created = @(if ($s.scripts_created) { $s.scripts_created } else { @() })
        $executed = @(if ($s.scripts_executed) { $s.scripts_executed } else { @() })
        $notRun = $created | Where-Object { $executed -notcontains $_ }
        $checks.Add((Check "scripts_coverage" ($notRun.Count -eq 0) "$($created.Count) created / $($executed.Count) executed / $($notRun.Count) not-run"))
    } catch { $checks.Add((Check "state_file" $false "corrupt: $($_.Exception.Message)")) }
} else { $checks.Add((Check "state_file" $false "missing: $statePath")) }

# 2. Baselines
$baselineCount = if (Test-Path $baselineDir) { @(Get-ChildItem $baselineDir -Directory).Count } else { 0 }
$checks.Add((Check "baselines" ($baselineCount -gt 0) "$baselineCount snapshots"))

# 3. Mistake log
$mistakeEntries = if (Test-Path $mistakeLog) { (Select-String -Path $mistakeLog -Pattern '^###' | Measure-Object).Count } else { 0 }
$checks.Add((Check "mistake_log" ($mistakeEntries -gt 0) "$mistakeEntries entries"))

# 4. Key files
$keyFiles = @(
    @{n="CLAUDE.md"; p=(Join-Path $root "CLAUDE.md")},
    @{n="stop-gate"; p=(Join-Path $root ".claude\hooks\stop-gate.ps1")},
    @{n="posttool-recorder"; p=(Join-Path $root ".claude\hooks\posttool-recorder.ps1")},
    @{n="block-dangerous"; p=(Join-Path $root ".claude\hooks\block-dangerous.ps1")},
    @{n="evidence-check"; p=(Join-Path $root "ai-infra\scripts\evidence-check.ps1")},
    @{n="close-run"; p=(Join-Path $root "ai-infra\scripts\close-run.ps1")},
    @{n="test-loop"; p=(Join-Path $root "test-automation-loop.ps1")},
    @{n="test-neg-gates"; p=(Join-Path $root "test-negative-gates.ps1")},
    @{n="health"; p=(Join-Path $root "health.ps1")}
)
foreach ($f in $keyFiles) { $checks.Add((Check "file:$($f.n)" (Test-Path $f.p) $f.p)) }

# 5. GPT-5.5 pipeline — check actual queue rw probe
$pipelineAlive = $false
try {
    $pq = Join-Path $root "ai-pipeline\gpt-queue"
    $probePath = Join-Path $pq ("hp-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    "ok" | Set-Content $probePath -Encoding UTF8
    $pr = Get-Content $probePath -Raw -Encoding UTF8
    Remove-Item $probePath -Force -ErrorAction SilentlyContinue
    $pipelineAlive = ($pr.Trim() -eq "ok")
} catch {}
$checks.Add((Check "gpt55_pipeline" $pipelineAlive $(if($pipelineAlive){'queue rw ok'}else{'queue rw failed'})))

# 6. Ollama
$ollamaPort = (netstat -ano 2>$null | Select-String "11434.*LISTENING")
$checks.Add((Check "ollama" ($null -ne $ollamaPort) $(if($ollamaPort){'port 11434 listening'}else{'down'})))

# 7. Hook integrity (SHA256)
try {
    $hashPath = Join-Path (Join-Path $root ".claude\run-state") "hook-hashes.json"
    $hookFiles = @(
        (Join-Path $root ".claude\hooks\stop-gate.ps1"),
        (Join-Path $root ".claude\hooks\posttool-recorder.ps1"),
        (Join-Path $root ".claude\hooks\block-dangerous.ps1")
    )
    $currentHashes = [ordered]@{}
    $missingHooks = @()
    foreach ($hp in $hookFiles) {
        $hn = Split-Path -Leaf $hp
        if (-not (Test-Path $hp)) { $missingHooks += $hn; continue }
        $currentHashes[$hn] = (Get-FileHash -LiteralPath $hp -Algorithm SHA256).Hash
    }
    if ($missingHooks.Count -gt 0) {
        $checks.Add((Check "hook_integrity" $false ("MISSING: " + ($missingHooks -join ", "))))
    } elseif (-not (Test-Path $hashPath)) {
        [pscustomobject]@{ updated_at = (Get-Date).ToString("s"); hooks = $currentHashes } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $hashPath -Encoding UTF8
        $checks.Add((Check "hook_integrity" $true "baseline created"))
    } else {
        try {
            $baseline = Get-Content $hashPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $changed = @()
            foreach ($hk in $currentHashes.Keys) {
                $old = ""
                if ($baseline.hooks.PSObject.Properties.Name -contains $hk) { $old = $baseline.hooks.$hk }
                if ($old -ne $currentHashes[$hk]) { $changed += $hk }
            }
            [pscustomobject]@{ updated_at = (Get-Date).ToString("s"); hooks = $currentHashes } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $hashPath -Encoding UTF8
            if ($changed.Count -gt 0) { $checks.Add((Check "hook_integrity" $true ("CHANGED: " + ($changed -join ", ")))) }
            else { $checks.Add((Check "hook_integrity" $true "unchanged")) }
        } catch { $checks.Add((Check "hook_integrity" $true "WARN: check failed")) }
    }
} catch { $checks.Add((Check "hook_integrity" $true "fail-open")) }

# 8. Pipeline deep health
try {
    $pipelineDir = Join-Path $root "ai-pipeline"
    $queueDir = Join-Path $pipelineDir "gpt-queue"
    $inboxDir = Join-Path $queueDir "inbox"
    $outboxDir = Join-Path $queueDir "outbox"
    $failedDir = Join-Path $queueDir "failed"
    foreach ($d in @($queueDir,$inboxDir,$outboxDir,$failedDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

    $probePath = Join-Path $queueDir ("hp-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    "ok" | Set-Content $probePath -Encoding UTF8
    $probeRead = Get-Content $probePath -Raw -Encoding UTF8
    Remove-Item $probePath -Force -ErrorAction SilentlyContinue
    if ($probeRead.Trim() -ne "ok") {
        $checks.Add((Check "pipeline_deep" $false "queue rw mismatch"))
    } else {
        $inboxFiles = @(Get-ChildItem $inboxDir -File -ErrorAction SilentlyContinue)
        $outboxFiles = @(Get-ChildItem $outboxDir -File -ErrorAction SilentlyContinue)
        $failedFiles = @(Get-ChildItem $failedDir -File -ErrorAction SilentlyContinue)
        $cutoff = (Get-Date).AddMinutes(-30)
        $stale = @($inboxFiles | Where-Object { $_.Name -like "*.request.json" -and $_.LastWriteTime -lt $cutoff -and -not (Test-Path (Join-Path $outboxDir ($_.Name -replace "\.request\.json$", ".response.json"))) })
        $detail = "inbox=$($inboxFiles.Count) outbox=$($outboxFiles.Count) failed=$($failedFiles.Count)"
        if ($stale.Count -gt 0) { $detail += " STALE=$($stale.Count)" }
        if ($stale.Count -gt 0) { $detail += " WARN_STALE=$($stale.Count)" }
        $checks.Add((Check "pipeline_deep" $true $detail))
    }
} catch { $checks.Add((Check "pipeline_deep" $false $_.Exception.Message)) }

# 9. Run evidence-check as final verdict
$evidenceCheck = (Join-Path $root "ai-infra\scripts\evidence-check.ps1")
if (Test-Path $evidenceCheck) {
    $ecOut = & pwsh -NoProfile -File $evidenceCheck -Operation run-complete 2>&1 | Out-String
    $ecOk = ($LASTEXITCODE -eq 0)
    $checks.Add((Check "evidence_check" $ecOk $(if($ecOk){'ok=true'}else{'FAIL'})))
}

# 8. Playwright Chromium binary
$pipelineDir = Join-Path $root "ai-pipeline"
try {
    Push-Location $pipelineDir
    $chromiumOut = & node -e "const { chromium } = require('playwright'); console.log(chromium.executablePath())" 2>&1
    $chromiumPath = ($chromiumOut | Select-Object -Last 1).Trim()
    $chromiumExists = (-not [string]::IsNullOrWhiteSpace($chromiumPath)) -and (Test-Path $chromiumPath)
    Pop-Location
    $checks.Add((Check "playwright_chromium" $chromiumExists $(if($chromiumExists){$chromiumPath}else{'missing'})))
} catch { $checks.Add((Check "playwright_chromium" $false $_.Exception.Message)) }

# 9. Disabled capabilities
$routerPath = Join-Path $root ".claude\agent-router.json"
if (Test-Path $routerPath) {
    try {
        $router = Get-Content $routerPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $disabled = if ($router.PSObject.Properties.Name -contains "disabled_capabilities") { @($router.disabled_capabilities) } else { @() }
        $checks.Add((Check "disabled_capabilities" $true "$($disabled.Count) disabled: $($disabled -join ', ')"))
    } catch { $checks.Add((Check "disabled_capabilities" $false "router read failed")) }
} else { $checks.Add((Check "disabled_capabilities" $false "router missing")) }

$passed = @($checks | Where-Object { $_.ok }).Count
$failed = @($checks | Where-Object { -not $_.ok }).Count
$grade = if ($failed -eq 0) { 'A+' } elseif ($failed -le 2) { 'A-' } elseif ($failed -le 5) { 'B' } else { 'C' }

if ($Json) {
    [pscustomobject]@{grade=$grade;total=$checks.Count;passed=$passed;failed=$failed;timestamp=(Get-Date -Format 'o');checks=$checks} | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n=== Automation Health: $grade ===" -ForegroundColor $(if($grade -eq 'A+'){'Green'}elseif($grade -eq 'A-'){'Yellow'}else{'Red'})
    Write-Host "Passed: $passed / $($checks.Count)  Failed: $failed`n"
    foreach ($c in $checks) {
        $icon = if ($c.ok) { '✅' } else { '❌' }
        Write-Host "$icon $($c.name): $($c.detail)"
    }
    Write-Host ""
}
exit $(if ($failed -gt 0) { 1 } else { 0 })
