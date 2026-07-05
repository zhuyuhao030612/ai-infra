# 代码图谱自动刷新
# 用法: pwsh -File symbols-refresh.ps1
$ErrorActionPreference = "Continue"
$CodeDir = "D:\Code"
$dbPath = "$CodeDir\ai-infra\data\symbols.sqlite"
$script = "$CodeDir\ai-infra\scripts\build-symbols.py"

Write-Host "[symbols] Refreshing code graph..."
$result = & python $script 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[symbols] Done"
    # Log event
    $stats = if (Test-Path $dbPath) {
        "size=$([Math]::Round((Get-Item $dbPath).Length/1KB,1))KB"
    } else { "failed" }
    & pwsh -File "$CodeDir\ai-infra\scripts\log-event.ps1" -Type "symbols.refresh" -Ok:$true -DataJson "{`"stats`":`"$stats`"}"
} else {
    Write-Host "[symbols] Failed: $result"
}
