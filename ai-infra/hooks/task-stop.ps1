# Task stop hook — evidence gate + completion signal
# Enhanced v2: checks evidence before marking complete
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootDir = if ($env:AI_ROOT) { $env:AI_ROOT } else { "D:\Code" }
$signalDir = "D:\Code\ai-infra\tasks\signals"
$runDir = "D:\Code\ai-infra\runtime"
New-Item -ItemType Directory -Force -Path $signalDir | Out-Null
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$ts = Get-Date -Format "o"
$runId = $env:AI_RUN_ID ?? (Get-Date -Format "yyyyMMdd-HHmmss")

# ---- Evidence gate: check if files were changed without tests ----
$runsDir = Join-Path $RootDir ".ai-state\runs"
$evidenceOk = $true
$gateReason = ""

if (Test-Path $runsDir) {
    $latest = Get-ChildItem $runsDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        $evidencePath = Join-Path $latest.FullName "evidence.jsonl"
        if (Test-Path $evidencePath) {
            try {
                $entries = Get-Content $evidencePath -Encoding UTF8 -ErrorAction SilentlyContinue |
                    Where-Object { $_ -notmatch '^#' -and $_.Trim() } |
                    ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } |
                    Where-Object { $null -ne $_ }

                $filesChanged = ($entries | Where-Object { $_.tool_name -in @("Edit","Write") -and $_.file_paths }).Count
                $testsFound = ($entries | Where-Object {
                    $input = if ($_.tool_input -is [string]) { $_.tool_input } else { ($_.tool_input | ConvertTo-Json -Depth 1 -Compress) }
                    $input -match 'pytest|vitest|jest|npm\s+test|cargo\s+test|go\s+test|ruff\s+check|ps-guard|evidence-check'
                }).Count

                if ($filesChanged -gt 0 -and $testsFound -eq 0) {
                    $evidenceOk = $false
                    $gateReason = "WARNING: $filesChanged file(s) changed, 0 tests run — evidence gap"
                }
            } catch {
                # Non-fatal: can't parse evidence, skip gate
            }
        } else {
            # No evidence file — may be a no-tool session, acceptable
        }
    }
}

# ---- Write stop signal ----
@{
    event = "Stop"
    ts = $ts
    status = "assistant_stopped"
    runId = $runId
    evidence_ok = $evidenceOk
    gate_reason = $gateReason
} | ConvertTo-Json | Out-File (Join-Path $signalDir "$runId.stopped") -Encoding UTF8

@{
    lastStop = $ts
    runId = $runId
    evidence_ok = $evidenceOk
    gate_reason = $gateReason
} | ConvertTo-Json | Out-File (Join-Path $runDir "last-stop.json") -Encoding UTF8
