# State machine transition engine for task lifecycle
# Usage: pwsh -File state-transition.ps1 -TaskId "task-xxx" -From "pending" -To "running"
param(
    [Parameter(Mandatory=$true)][string]$TaskId,
    [Parameter(Mandatory=$true)][string]$From,
    [Parameter(Mandatory=$true)][string]$To,
    [string]$Reason = ""
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Valid transition map
$validTransitions = @{
    "pending"   = @("running")
    "running"   = @("completed", "failed", "blocked")
    "blocked"   = @("running")
    "failed"    = @("pending")
    "completed" = @()
}

# Check transition validity
$allowed = $validTransitions[$From]
if (-not $allowed -or $To -notin $allowed) {
    $err = @{
        ok = $false
        error = "Invalid transition: $From -> $To"
        allowed = $allowed
        task_id = $TaskId
    } | ConvertTo-Json -Compress
    Write-Output $err
    exit 1
}

$ts = Get-Date -Format "o"
$transition = @{
    from = if ($From -eq "null") { $null } else { $From }
    to = $To
    ts = $ts
    reason = if ($Reason) { $Reason } else { "State transition: $From -> $To" }
}

# Update task JSON if run directory exists
$RootDir = if ($env:AI_ROOT) { $env:AI_ROOT } else { "D:\Code" }
$RunsDir = Join-Path $RootDir ".ai-state\runs"

# Find run directory for this task
$runDir = $null
if (Test-Path $RunsDir) {
    $candidates = Get-ChildItem $RunsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$TaskId*" -or $_.Name -eq $TaskId } |
        Sort-Object LastWriteTime -Descending
    $runDir = if ($candidates) { $candidates[0].FullName } else { $null }
}

if ($runDir) {
    $taskJsonPath = Join-Path $runDir "task.json"
    if (Test-Path $taskJsonPath) {
        try {
            $taskData = Get-Content $taskJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $existingTransitions = if ($taskData.transitions) { @($taskData.transitions) } else { @() }
            $existingTransitions += $transition
            # Convert back — preserve existing fields
            $updated = [ordered]@{}
            foreach ($prop in $taskData.PSObject.Properties) {
                if ($prop.Name -eq "transitions") {
                    $updated["transitions"] = @($existingTransitions)
                } elseif ($prop.Name -eq "status") {
                    $updated["status"] = $To
                } else {
                    $updated[$prop.Name] = $prop.Value
                }
            }
            # Write atomically
            $tmp = "$taskJsonPath.tmp.$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            $updated | ConvertTo-Json -Depth 6 | Out-File $tmp -Encoding UTF8 -NoNewline
            Move-Item $tmp $taskJsonPath -Force
        } catch {
            Write-Warning "Failed to update task.json: $_"
        }
    }
}

# Also log to timeline if run dir exists
if ($runDir) {
    $timelineFile = Join-Path $runDir "timeline.jsonl"
    $timelineEntry = @{
        ts = $ts
        step = "state-transition"
        status = $To
        from = $From
        reason = if ($Reason) { $Reason } else { "" }
    } | ConvertTo-Json -Compress
    try {
        Add-Content -Path $timelineFile -Value $timelineEntry -Encoding UTF8
    } catch {}
}

# Update .ai-state/state.json task_status
$stateFile = Join-Path $RootDir ".ai-state\state.json"
if (Test-Path $stateFile) {
    try {
        $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $state.task_status = if ($To -in @("completed", "failed")) { "idle" } else { "running" }
        $state.updated_at = (Get-Date).ToUniversalTime().ToString("o")
        $tmp = "$stateFile.tmp.$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        $state | ConvertTo-Json -Depth 8 | Out-File $tmp -Encoding UTF8 -NoNewline
        Move-Item $tmp $stateFile -Force
    } catch {}
}

$result = @{
    ok = $true
    task_id = $TaskId
    from = $From
    to = $To
    ts = $ts
    run_dir = $runDir
} | ConvertTo-Json -Compress

Write-Output $result
exit 0
