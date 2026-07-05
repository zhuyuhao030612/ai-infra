#requires -Version 5.1
<# Capability usage audit. Reports which scripts are actually used.
   Usage: pwsh -File capability-usage-report.ps1                    (full report)
          pwsh -File capability-usage-report.ps1 -MarkUsage "script" exit_code duration_ms  (record) #>
param([string]$MarkUsage = "", [int]$ExitCode = 0, [int]$DurationMs = 0)

$ErrorActionPreference = "Continue"
$root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { "D:\Code" }
$usagePath = Join-Path $root ".claude\run-state\capability-usage.jsonl"
$stateDir = Split-Path -Parent $usagePath
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

# Mark mode: record a single usage
if ($MarkUsage) {
    try {
        $rec = [ordered]@{ time = (Get-Date).ToString("s"); script = $MarkUsage; capability = [IO.Path]::GetFileNameWithoutExtension($MarkUsage); exit_code = $ExitCode; duration_ms = $DurationMs; success = ($ExitCode -eq 0) }
        ($rec | ConvertTo-Json -Depth 5 -Compress) | Add-Content $usagePath -Encoding UTF8
        exit 0
    } catch { exit 0 }
}

# Report mode
$records = @()
if (Test-Path $usagePath) {
    Get-Content $usagePath -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() } | ForEach-Object {
        try { $records += ($_ | ConvertFrom-Json) } catch {}
    }
}

if ($records.Count -eq 0) { Write-Host "无使用记录。"; exit 0 }

$now = Get-Date
$groups = $records | Group-Object -Property script
$summary = @()
foreach ($g in $groups) {
    $items = @($g.Group)
    $c = $items.Count; $s = @($items | Where-Object { $_.success }).Count
    $last = ($items | Sort-Object { [datetime]$_.time } -Descending | Select-Object -First 1).time
    $age = [math]::Round(($now - [datetime]$last).TotalDays, 1)
    $durs = @($items | ForEach-Object { [int]$_.duration_ms })
    $avg = if ($durs.Count -gt 0) { [math]::Round(($durs | Measure-Object -Average).Average) } else { 0 }
    if ($age -le 7) { $bucket = "活跃"; $color = "Green" }
    elseif ($age -ge 60) { $bucket = "休眠"; $color = "Red" }
    elseif ($age -ge 30) { $bucket = "低频"; $color = "Yellow" }
    else { $bucket = "观察"; $color = "DarkYellow" }
    $summary += [pscustomobject]@{ script=$g.Name; calls=$c; success_rate=[math]::Round($s/$c*100,1); last=$last; age_days=$age; avg_duration_ms=$avg; bucket=$bucket; color=$color }
}

$active = @($summary | Where-Object { $_.bucket -eq "活跃" })
$watch  = @($summary | Where-Object { $_.bucket -eq "观察" })
$low    = @($summary | Where-Object { $_.bucket -eq "低频" })
$sleep  = @($summary | Where-Object { $_.bucket -eq "休眠" })

Write-Host "Capability Usage: $($records.Count) records, $($summary.Count) scripts"
foreach ($set in @(@{n="活跃(7d)"; items=$active; c="Green"}, @{n="观察(8-29d)"; items=$watch; c="DarkYellow"}, @{n="低频(30-59d)"; items=$low; c="Yellow"}, @{n="休眠(60d+)"; items=$sleep; c="Red"})) {
    Write-Host "`n--- $($set.n) ---" -ForegroundColor $set.c
    if ($set.items.Count -eq 0) { Write-Host " none" }
    foreach ($i in ($set.items | Sort-Object age_days -Descending)) {
        Write-Host "  $($i.script): $($i.calls) calls, $($i.success_rate)%, $($i.age_days)d ago" -ForegroundColor $set.c
    }
}

$report = [pscustomobject]@{ generated_at = (Get-Date).ToString("s"); total_records = $records.Count; total_scripts = $summary.Count; active = $active; watch = $watch; low = $low; sleeping = $sleep }
$reportPath = Join-Path $stateDir "capability-usage-report.json"
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host "`nreport: $reportPath"
exit 0
