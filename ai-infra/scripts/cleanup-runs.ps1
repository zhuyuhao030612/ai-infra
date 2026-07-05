# 清理过期文件 v2 — 默认 dry-run，防误删
# 用法: pwsh -File cleanup-runs.ps1            (试运行，不删)
#       pwsh -File cleanup-runs.ps1 -Apply     (实际删除)
#       pwsh -File cleanup-runs.ps1 -Days 14 -Apply
param(
    [int]$Days = 7,
    [switch]$Apply,
    [switch]$All
)

$ErrorActionPreference = "Continue"
$CodeDir = "D:\Code"
$RunsDir = "$CodeDir\.ai-state\runs"
$GptRunsDir = "$CodeDir\ai-pipeline\gpt-runs"
$GptCacheDir = "$CodeDir\ai-pipeline\gpt-cache"
$FailuresDir = "$CodeDir\ai-infra\failures"
$EventsLog = "$CodeDir\ai-infra\logs\events.jsonl"
$totalRemoved = 0
$totalSkipped = 0

if (-not $Apply) {
    Write-Host "=== DRY RUN (未指定 -Apply，不会删除) ==="
} else {
    Write-Host "=== 实际删除模式 (-Apply) ==="
}
Write-Host ""

function Should-Skip($itemPath, $minAgeHours = 1) {
    # Skip if .lock file exists in the directory
    if (Test-Path "$itemPath\*.lock") { return $true }
    # Skip if manifest.json has status=writing or status=running
    $manifest = "$itemPath\manifest.json"
    if (Test-Path $manifest) {
        try {
            $m = Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($m.status -in @('writing', 'running')) { return $true }
        } catch {}
    }
    # Skip if recently modified (< minAgeHours)
    $age = [DateTime]::Now - (Get-Item $itemPath).LastWriteTime
    if ($age.TotalHours -lt $minAgeHours) { return $true }
    # Skip 'latest' symlinks or markers
    if ((Split-Path $itemPath -Leaf) -eq 'latest') { return $true }
    return $false
}

function Clean-Dir($dir, $label, $retentionDays, $minAgeHours = 1) {
    $count = 0
    if (-not (Test-Path $dir)) {
        Write-Host "[$label] 目录不存在"
        return 0
    }

    $cutoff = [DateTime]::Now.AddDays(-$retentionDays)
    $items = Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff }

    if ($All) {
        $items = Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue
    }

    foreach ($item in $items) {
        $age = [Math]::Round(([DateTime]::Now - $item.LastWriteTime).TotalDays)
        if (Should-Skip $item.FullName $minAgeHours) {
            Write-Host "  [SKIP] $($item.Name) (locked/running/recent)"
            $script:totalSkipped++
            continue
        }
        if (-not $Apply) {
            Write-Host "  [DRY] Would remove: $($item.Name) (${age}d old)"
        } else {
            Remove-Item $item.FullName -Recurse -Force
            Write-Host "  Removed: $($item.Name) (${age}d old)"
        }
        $count++
    }

    if ($count -eq 0) {
        Write-Host "[$label] 无过期项"
    } else {
        $action = if ($Apply) { "清理" } else { "将清理" }
        Write-Host "[$label] $action $count 项"
    }
    return $count
}

# Clean task runs
$totalRemoved += Clean-Dir $RunsDir "任务运行 (.ai-state/runs)" $Days

# Clean GPT failure artifacts
$totalRemoved += Clean-Dir $GptRunsDir "GPT 超时证据包 (gpt-runs)" $Days

# Clean failure evidence packs (older than retention, no writing status)
$totalRemoved += Clean-Dir $FailuresDir "失败证据包 (failures)" $Days

# Clean GPT cache (>24h old, TTL is 1h so 24h is safe)
$cacheItems = Get-ChildItem $GptCacheDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt [DateTime]::Now.AddHours(-24) }
if ($All) { $cacheItems = Get-ChildItem $GptCacheDir -File -ErrorAction SilentlyContinue }
if (-not $Apply) {
    Write-Host "[缓存] 将删除: $($cacheItems.Count) 过期项 (>24h)"
    $totalRemoved += $cacheItems.Count
} elseif ($cacheItems) {
    $cacheItems | Remove-Item -Force
    Write-Host "[缓存] Removed $($cacheItems.Count) expired entries"
    $totalRemoved += $cacheItems.Count
} else {
    Write-Host "[缓存] 无过期缓存"
}

# Events log size warning (never auto-delete, just warn)
if (Test-Path $EventsLog) {
    $sizeMB = [Math]::Round((Get-Item $EventsLog).Length / 1MB, 1)
    if ($sizeMB -gt 50) {
        Write-Host "[事件日志] ⚠️ events.jsonl = ${sizeMB}MB — 建议按日期切分"
    } else {
        Write-Host "[事件日志] ${sizeMB}MB OK"
    }
}

Write-Host ""
Write-Host "=== 总计: $totalRemoved 项" + $(if ($totalSkipped -gt 0) { " (跳过 $totalSkipped 项locked/running/recent)" } else { "" }) + " ==="
if (-not $Apply) {
    Write-Host "提示: 使用 -Apply 执行实际删除"
}
