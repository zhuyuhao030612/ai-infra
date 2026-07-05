# 巡检脚本：扫描 .agent/jobs.json，超时写 overdue.json
param(
    [string]$RootDir = 'D:\Code',
    [string]$JobsFile = '',
    [string]$OverdueFile = '',
    [string]$HealthLog = '',
    [int]$DefaultMaxSilentMinutes = 30
)
if (-not $JobsFile) { $JobsFile = Join-Path $RootDir '.agent\jobs.json' }
if (-not $OverdueFile) { $OverdueFile = Join-Path $RootDir '.agent\overdue.json' }
if (-not $HealthLog) { $HealthLog = Join-Path $RootDir '.agent\health-checks.log' }

$ErrorActionPreference = 'Continue'
$now = Get-Date

function log($msg) {
    $line = "$($now.ToString('yyyy-MM-dd HH:mm:ss')) $msg"
    Write-Host $line
    Add-Content -Path $HealthLog -Value $line -ErrorAction SilentlyContinue
}

if (-not (Test-Path $JobsFile)) {
    log "no jobs file, skip"
    exit 0
}

try {
    $jobs = Get-Content $JobsFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    log "jobs.json parse error: $_"
    exit 1
}

$overdue = @()
$nowEpoch = [DateTimeOffset]::new($now).ToUnixTimeSeconds()

foreach ($jobId in $jobs.PSObject.Properties.Name) {
    $j = $jobs.$jobId
    if ($j.status -ne 'running') { continue }

    if (-not $j.next_check_at_epoch) {
        $j.next_check_at_epoch = $nowEpoch
        log "INIT: $jobId next_check_at_epoch initialized"
        continue
    }

    $nextCheck = $j.next_check_at_epoch
    $maxSilent = if ($j.max_silent_minutes) { $j.max_silent_minutes * 60 } else { $DefaultMaxSilentMinutes * 60 }
    $deadline = [int]$nextCheck + $maxSilent

    if ($nowEpoch -gt $deadline) {
        $item = [ordered]@{
            job_id = $jobId
            command = $j.command
            started_at = $j.started_at
            next_check_at_epoch = $nextCheck
            max_silent_minutes = $j.max_silent_minutes
            overdue_since = (Get-Date -Date "1970-01-01" -AsUTC).AddSeconds($deadline).ToString('yyyy-MM-dd HH:mm:ss')
            required_action = 'check logs and update next_check_at or mark failed'
        }
        $overdue += $item
        log "OVERDUE: $jobId (started $($j.started_at), next_check_at_epoch=$nextCheck, now=$nowEpoch)"
    }
}

if ($overdue.Count -gt 0) {
    $overdue | ConvertTo-Json -Depth 4 | Set-Content -Path $OverdueFile -Encoding UTF8
    log "wrote $($overdue.Count) overdue jobs to overdue.json"
} else {
    log "all jobs healthy"
}
