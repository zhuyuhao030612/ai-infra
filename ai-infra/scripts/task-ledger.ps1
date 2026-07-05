# Task ledger — cost + evidence summary for deterministic control plane
# Usage: pwsh -File task-ledger.ps1 [-RunDir <path>] [-TaskId <id>] [-SummaryOnly]
# Wired as Stop hook or standalone. Outputs ledger.json in run directory.
param(
    [string]$RunDir = "",
    [string]$TaskId = "",
    [switch]$SummaryOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootDir = if ($env:AI_ROOT) { $env:AI_ROOT } else { "D:\Code" }
$RunsDir = Join-Path $RootDir ".ai-state\runs"

# ---- resolve run directory ----
if ($RunDir -and (Test-Path $RunDir)) {
    $runPath = $RunDir
} else {
    if (-not (Test-Path $RunsDir)) {
        Write-Output (@{ok=$false; reason="No runs directory"} | ConvertTo-Json -Compress)
        exit 1
    }
    $latest = Get-ChildItem $RunsDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        Write-Output (@{ok=$false; reason="No runs found"} | ConvertTo-Json -Compress)
        exit 1
    }
    $runPath = $latest.FullName
}

$evidencePath = Join-Path $runPath "evidence.jsonl"
$ledgerPath = Join-Path $runPath "ledger.json"

# ---- risk classification ----
function Get-RiskLevel($toolName, $toolInput) {
    $inputStr = if ($toolInput -is [string]) { $toolInput } else { ($toolInput | ConvertTo-Json -Depth 2 -Compress) }

    # L5: production/irreversible — Remove-Item -Recurse, Stop-Process, format/delete
    if ($toolName -in @("PowerShell","Bash") -and $inputStr -match 'Remove-Item\s+-Recurse|rm\s+-rf|Stop-Process|Format-Volume|DROP\s+|DELETE\s+FROM') {
        return 5
    }
    # L4: exec, SSH, credentials, browser profile, external download
    if ($inputStr -match 'SSH|\.pem|\.key|token|credential|browser-profile|Invoke-WebRequest.*download|Start-Process.*node') {
        return 4
    }
    # L3: delete, overwrite, move, kill, desktop click, install
    if ($toolName -eq "Edit" -or $toolName -eq "Write" -or
        $inputStr -match 'Remove-Item|rm\s|Move-Item|kill|Stop-Service|npm\s+install|pip\s+install|uv\s+install') {
        return 3
    }
    # L2: behavior change
    if ($toolName -in @("PowerShell","Bash") -and $inputStr -match 'Set-|New-|Start-|Enable-') {
        return 2
    }
    # L1: safe write within workspace
    return 1
}

# ---- detect if tests were run ----
function Get-TestsRun($entries) {
    $testRuns = @()
    foreach ($e in $entries) {
        $input = if ($e.tool_input -is [string]) { $e.tool_input } else { ($e.tool_input | ConvertTo-Json -Depth 1 -Compress) }
        if ($e.tool_name -in @("PowerShell","Bash") -and $input -match 'pytest|vitest|jest|npm\s+test|cargo\s+test|go\s+test|ruff\s+check|ps-guard|evidence-check') {
            $testRuns += @{
                ts = $e.ts
                tool = $e.tool_name
                match = ($input | Select-String -Pattern 'pytest|vitest|jest|npm\s+test|cargo\s+test|go\s+test|ruff\s+check|ps-guard|evidence-check' -AllMatches).Matches.Value -join ', '
            }
        }
    }
    return $testRuns
}

# ---- detect models used ----
function Get-ModelsUsed($entries) {
    $models = @{}
    foreach ($e in $entries) {
        $input = if ($e.tool_input -is [string]) { $e.tool_input } else { ($e.tool_input | ConvertTo-Json -Depth 3 -Compress) }

        if ($e.tool_name -eq "Agent" -and $input -match '"model"\s*:\s*"([^"]+)"') {
            $m = $Matches[1]
            if (-not $models.ContainsKey($m)) { $models[$m] = 0 }
            $models[$m]++
        }
        if ($e.tool_name -eq "PowerShell" -and $input -match 'gpt-ask\.ps1') {
            if (-not $models.ContainsKey("gpt-5.5")) { $models["gpt-5.5"] = 0 }
            $models["gpt-5.5"]++
        }
        if ($e.tool_name -eq "WebSearch") {
            if (-not $models.ContainsKey("web-search")) { $models["web-search"] = 0 }
            $models["web-search"]++
        }
        if ($input -match 'ollama|qwen') {
            if (-not $models.ContainsKey("ollama-qwen2.5-coder")) { $models["ollama-qwen2.5-coder"] = 0 }
            $models["ollama-qwen2.5-coder"]++
        }
    }
    # main model is always deepseek-v4
    if ($entries.Count -gt 0) {
        if (-not $models.ContainsKey("deepseek-v4")) { $models["deepseek-v4"] = 1 }
    }
    return $models
}

# ---- main ----
if (-not (Test-Path $evidencePath)) {
    $ledger = @{
        ok = $false
        task_id = if ($TaskId) { $TaskId } else { Split-Path -Leaf $runPath }
        run_dir = $runPath
        reason = "No evidence.jsonl found — no tool calls recorded"
        generated_at = (Get-Date -Format "o")
    }
    $ledger | ConvertTo-Json -Depth 4 | Out-File $ledgerPath -Encoding UTF8
    if (-not $SummaryOnly) { Write-Output ($ledger | ConvertTo-Json -Depth 4) }
    exit 1
}

# Parse evidence
$entries = Get-Content $evidencePath -Encoding UTF8 -ErrorAction SilentlyContinue |
    Where-Object { $_ -notmatch '^#' -and $_.Trim() } |
    ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } |
    Where-Object { $null -ne $_ }

if ($entries.Count -eq 0) {
    $ledger = @{
        ok = $false
        task_id = if ($TaskId) { $TaskId } else { Split-Path -Leaf $runPath }
        run_dir = $runPath
        reason = "Empty evidence.jsonl"
        generated_at = (Get-Date -Format "o")
    }
    $ledger | ConvertTo-Json -Depth 4 | Out-File $ledgerPath -Encoding UTF8
    if (-not $SummaryOnly) { Write-Output ($ledger | ConvertTo-Json -Depth 4) }
    exit 1
}

# Tool counts
$toolCounts = $entries | Group-Object -Property tool_name | ForEach-Object { @{$_.Name = $_.Count} } | ForEach-Object { $_ }
$toolSummary = @{}
foreach ($g in ($entries | Group-Object -Property tool_name)) {
    $toolSummary[$g.Name] = $g.Count
}

# Files changed (from Edit/Write tool calls)
$filesChanged = @()
foreach ($e in $entries) {
    if ($e.tool_name -in @("Edit","Write") -and $e.file_paths) {
        $filesChanged += $e.file_paths
    }
}
$filesChanged = @($filesChanged | Select-Object -Unique)

# Evidence collected
$evidenceItems = @()
foreach ($e in $entries) {
    if ($e.tool_name -in @("mcp__playwright__browser_take_screenshot","Read","Glob","Grep") -and $e.outcome -eq "success") {
        $evidenceItems += @{ ts = $e.ts; tool = $e.tool_name }
    }
}

# Max risk level
$maxRisk = 1
foreach ($e in $entries) {
    $input = if ($e.tool_input -is [string]) { $e.tool_input } else { ($e.tool_input | ConvertTo-Json -Depth 2 -Compress) }
    $r = Get-RiskLevel $e.tool_name $input
    if ($r -gt $maxRisk) { $maxRisk = $r }
}

# External API calls
$externalCalls = ($entries | Where-Object { $_.tool_name -in @("WebSearch","WebFetch","mcp__playwright__browser_navigate") }).Count

# Tests run
$testsRun = Get-TestsRun $entries

# Models used
$modelsUsed = Get-ModelsUsed $entries

# Build ledger
$ledger = [ordered]@{
    ok = $true
    task_id = if ($TaskId) { $TaskId } else { Split-Path -Leaf $runPath }
    run_dir = $runPath
    generated_at = (Get-Date -Format "o")
    summary = [ordered]@{
        total_tool_calls = $entries.Count
        tools_breakdown = $toolSummary
        files_changed = $filesChanged
        files_changed_count = $filesChanged.Count
        tests_run = $testsRun
        tests_run_count = $testsRun.Count
        evidence_items = $evidenceItems.Count
        external_api_calls = $externalCalls
        max_risk_level = $maxRisk
    }
    models_used = $modelsUsed
    verdict = if ($filesChanged.Count -gt 0 -and $testsRun.Count -eq 0) {
        "WARNING: files changed without tests"
    } elseif ($maxRisk -ge 4) {
        "HIGH_RISK: L4+ operations detected"
    } else {
        "OK"
    }
}

# Save
$ledger | ConvertTo-Json -Depth 5 | Out-File $ledgerPath -Encoding UTF8

if (-not $SummaryOnly) {
    Write-Output ($ledger | ConvertTo-Json -Depth 5)
}

# Also update state.json with latest ledger info
$statePath = Join-Path $RootDir ".ai-state\state.json"
if (Test-Path $statePath) {
    try {
        $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $state | Add-Member -NotePropertyName "last_ledger" -NotePropertyValue @{
            task_id = $ledger.task_id
            ts = $ledger.generated_at
            verdict = $ledger.verdict
            files_changed = $filesChanged.Count
            tests_run = $testsRun.Count
        } -Force
        $state | ConvertTo-Json -Depth 5 | Out-File $statePath -Encoding UTF8
    } catch {
        # Non-fatal
    }
}

exit 0
