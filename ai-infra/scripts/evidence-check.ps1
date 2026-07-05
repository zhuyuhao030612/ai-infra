# Evidence check — verify evidence exists before permitting risky operations
# Usage: pwsh -File evidence-check.ps1 -Operation validate -Target "D:\Code\some\file.ps1"
#        pwsh -File evidence-check.ps1 -Operation run-complete
#        pwsh -File evidence-check.ps1 -Operation run-complete -RequireCloseRun
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("validate","read-before-write","schema-check","path-exists","run-complete")]
    [string]$Operation,

    [Parameter(Mandatory=$false)]
    [string]$Target = "",

    [string]$EvidenceDir = "",

    [switch]$RequireCloseRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# AI Runtime guard
$guardModule = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib') 'AIRuntime.psm1'
if (Test-Path $guardModule) {
  Import-Module $guardModule -Force -ErrorAction SilentlyContinue
  if ($env:AI_ORCHESTRATED -ne '1') {
    Write-Warning "evidence-check.ps1 应通过 ai.ps1 调用。直接调用将在未来版本阻止。"
  }
}

$RootDir = if ($env:AI_ROOT) { $env:AI_ROOT } else { "D:\Code" }

# Find the active run's evidence.jsonl
function Find-EvidencePath {
    $runsDir = Join-Path $RootDir ".ai-state\runs"
    if (-not (Test-Path $runsDir)) { return $null }

    # If EvidenceDir specified, use it
    if ($EvidenceDir -and (Test-Path $EvidenceDir)) {
        $candidate = Join-Path $EvidenceDir "evidence.jsonl"
        if (Test-Path $candidate) { return $candidate }
    }

    # Find most recent run with evidence.jsonl
    $latest = Get-ChildItem $runsDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        $path = Join-Path $latest.FullName "evidence.jsonl"
        if (Test-Path $path) { return $path }
    }
    return $null
}

$evidencePath = Find-EvidencePath

switch ($Operation) {
    "validate" {
        # Check if the target exists and is within project
        $resolved = try { [IO.Path]::GetFullPath($Target) } catch { $null }
        if (-not $resolved) {
            Write-Output (@{ok=$false; operation="validate"; target=$Target; reason="Cannot resolve path"} | ConvertTo-Json -Compress)
            exit 1
        }
        $inProject = $resolved.StartsWith($RootDir, [StringComparison]::OrdinalIgnoreCase)
        $exists = Test-Path $resolved

        if (-not $inProject) {
            Write-Output (@{ok=$false; operation="validate"; target=$resolved; reason="Target outside project root: $RootDir"} | ConvertTo-Json -Compress)
            exit 1
        }
        if ($exists -and (Get-Item $resolved -ErrorAction SilentlyContinue).PSIsContainer) {
            Write-Output (@{ok=$true; operation="validate"; target=$resolved; evidence="Target is a directory — validation passed"} | ConvertTo-Json -Compress)
            exit 0
        }
        if (-not $exists) {
            Write-Output (@{ok=$false; operation="validate"; target=$resolved; reason="Target does not exist"} | ConvertTo-Json -Compress)
            exit 1
        }
        Write-Output (@{ok=$true; operation="validate"; target=$resolved; evidence="Target exists within project"} | ConvertTo-Json -Compress)
        exit 0
    }

    "read-before-write" {
        # Check if the target file was read (recorded in evidence.jsonl)
        if (-not $evidencePath) {
            Write-Output (@{ok=$false; operation="read-before-write"; target=$Target; reason="No evidence.jsonl found — no active run or no evidence recorded"} | ConvertTo-Json -Compress)
            exit 1
        }
        $normalizedTarget = [IO.Path]::GetFullPath($Target)
        $readEvidence = Get-Content $evidencePath -Encoding UTF8 -ErrorAction SilentlyContinue |
            Where-Object { $_ -notmatch '^#' -and $_.Trim() } |
            ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } |
            Where-Object { $null -ne $_ -and $_.tool_name -in @("Read","Glob","Grep") -and $_.file_paths -and ($_.file_paths -contains $normalizedTarget) }

        if ($readEvidence) {
            Write-Output (@{ok=$true; operation="read-before-write"; target=$normalizedTarget; evidence=@($readEvidence | Select-Object -First 3 | ForEach-Object { $_.ts })} | ConvertTo-Json -Compress)
            exit 0
        } else {
            Write-Output (@{ok=$false; operation="read-before-write"; target=$normalizedTarget; reason="No evidence that target was read. Read the file first."} | ConvertTo-Json -Compress)
            exit 1
        }
    }

    "schema-check" {
        # Check if a JSON file exists and is valid
        if (-not (Test-Path $Target)) {
            Write-Output (@{ok=$false; operation="schema-check"; target=$Target; reason="File does not exist"} | ConvertTo-Json -Compress)
            exit 1
        }
        try {
            $content = Get-Content $Target -Raw -Encoding UTF8
            $null = $content | ConvertFrom-Json
            Write-Output (@{ok=$true; operation="schema-check"; target=$Target; evidence="Valid JSON"} | ConvertTo-Json -Compress)
            exit 0
        } catch {
            Write-Output (@{ok=$false; operation="schema-check"; target=$Target; reason="Invalid JSON: $($_.Exception.Message)"} | ConvertTo-Json -Compress)
            exit 1
        }
    }

    "path-exists" {
        if (Test-Path $Target) {
            Write-Output (@{ok=$true; operation="path-exists"; target=$Target; evidence="Path exists"} | ConvertTo-Json -Compress)
            exit 0
        } else {
            Write-Output (@{ok=$false; operation="path-exists"; target=$Target; reason="Path does not exist"} | ConvertTo-Json -Compress)
            exit 1
        }
    }

    "run-complete" {
        # One-command boss-standard audit. Checks: tests_run, evidence_collected, guard_used,
        # scripts_created vs scripts_executed, close_run_done (if -RequireCloseRun),
        # state consistency (close_run_done=true + tests_run=false = error).
        try {
            $projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { "D:\Code" }
            $statePath = Join-Path $projectDir ".claude\run-state\current.json"
            if (-not (Test-Path -LiteralPath $statePath)) {
                Write-Output (@{ok=$true; fail_open=$true; operation="run-complete"; warnings=@("current.json not found — nothing to audit")} | ConvertTo-Json -Depth 5)
                exit 0
            }

            $s = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $errors = [System.Collections.Generic.List[string]]::new()
            $warns  = [System.Collections.Generic.List[string]]::new()

            # Helper: check waiver presence
            function Test-W { param($Name)
                if ($s.PSObject.Properties.Name -notcontains "waivers" -or $null -eq $s.waivers) { return $false }
                return ($s.waivers | ConvertTo-Json -Depth 5 -Compress) -match [regex]::Escape($Name)
            }

            # 1. tests_run
            if ($s.PSObject.Properties.Name -notcontains "tests_run" -or $s.tests_run -ne $true) {
                if (Test-W "skip-tests") { $warns.Add("tests_run=false (skip-tests waiver)") }
                else { $errors.Add("tests_run=false") }
            }

            # 2. evidence_collected
            if ($s.PSObject.Properties.Name -notcontains "evidence_collected" -or $s.evidence_collected -ne $true) {
                if (Test-W "skip-evidence") { $warns.Add("evidence_collected=false (skip-evidence waiver)") }
                else { $errors.Add("evidence_collected=false") }
            }

            # 3. guard_used
            if ($s.PSObject.Properties.Name -notcontains "guard_used" -or $s.guard_used -ne $true) {
                $errors.Add("guard_used=false")
            }

            # 4. scripts created vs executed
            $created = @(); $executed = @()
            if ($s.PSObject.Properties.Name -contains "scripts_created" -and $null -ne $s.scripts_created) {
                $created = @($s.scripts_created)
            }
            if ($s.PSObject.Properties.Name -contains "scripts_executed" -and $null -ne $s.scripts_executed) {
                $executed = @($s.scripts_executed)
            }
            $notRun = @($created | Where-Object { $_ -and $executed -notcontains $_ })
            if (@($notRun).Count -gt 0) {
                if (Test-W "script-not-run") { $warns.Add("scripts not executed: $($notRun -join ', ') (waiver)") }
                else { $errors.Add("scripts_created_not_executed: $($notRun -join ', ')") }
            }

            # 5. close_run_done (only when -RequireCloseRun)
            if ($RequireCloseRun) {
                if ($s.PSObject.Properties.Name -notcontains "close_run_done" -or $s.close_run_done -ne $true) {
                    $errors.Add("close_run_done=false")
                }
            }

            # 6. State consistency
            if ($s.PSObject.Properties.Name -contains "close_run_done" -and $s.PSObject.Properties.Name -contains "tests_run") {
                if ($s.close_run_done -eq $true -and $s.tests_run -ne $true) {
                    $errors.Add("state_inconsistent: close_run_done=true but tests_run=false")
                }
            }

            $ok = ($errors.Count -eq 0)
            $sTestsRun = if ($s.PSObject.Properties.Name -contains "tests_run") { $s.tests_run } else { $null }
            $sEvidence = if ($s.PSObject.Properties.Name -contains "evidence_collected") { $s.evidence_collected } else { $null }
            $sCloseRun = if ($s.PSObject.Properties.Name -contains "close_run_done") { $s.close_run_done } else { $null }

            $result = @{
                ok = $ok
                operation = "run-complete"
                require_close_run = [bool]$RequireCloseRun
                tests_run = $sTestsRun
                evidence_collected = $sEvidence
                close_run_done = $sCloseRun
                scripts_created_count = @($created).Count
                scripts_not_executed = @($notRun)
                errors = @($errors)
                warnings = @($warns)
            }
            Write-Output ($result | ConvertTo-Json -Depth 5)
            $exitCode = if ($ok) { 0 } else { 1 }
            exit $exitCode
        } catch {
            Write-Output (@{ok=$true; fail_open=$true; operation="run-complete"; warnings=@("Exception: $($_.Exception.Message)")} | ConvertTo-Json -Depth 5)
            exit 0
        }
    }
}
