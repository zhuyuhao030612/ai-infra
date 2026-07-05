# 记忆检索 — 返回相关历史，不是全文
param([Parameter(Mandatory=$true,Position=0)][string]$Query, [int]$Limit=5)

$MemoryDir = "D:\Code\ai-infra\memory"
$results = @()

foreach ($f in @("sessions.jsonl","decisions.jsonl","failures.jsonl")) {
    $path = Join-Path $MemoryDir $f
    if (-not (Test-Path $path)) { continue }
    Get-Content $path | ForEach-Object {
        try { $e = $_ | ConvertFrom-Json; if ($e) { $results += $e } } catch {}
    }
}

# Score by keyword match
$kwList = $Query -split '\s+' | Where-Object { $_.Length -gt 1 }
$scored = $results | ForEach-Object {
    $score = 0
    $r = $_
    foreach ($kw in $kwList) {
        $kwLower = $kw.ToLower()
        if ($r.summary.ToLower() -match $kwLower) { $score += 3 }
        if ($r.decision.ToLower() -match $kwLower) { $score += 2 }
        foreach ($t in $r.topic) { if ($t.ToLower() -match $kwLower) { $score += 4 } }
    }
    [pscustomobject]@{score=$score; entry=$r}
} | Where-Object { $_.score -gt 0 } | Sort-Object score -Descending | Select-Object -First $Limit

if ($scored.Count -eq 0) {
    Write-Host "[memory] No matches for: $Query"
    return
}

Write-Host "=== Memory: $($scored.Count) matches ==="
foreach ($s in $scored) {
    $e = $s.entry
    Write-Host "  [$($e.type)] $($e.summary)"
    if ($e.decision) { Write-Host "    结论: $($e.decision)" }
    Write-Host "    ($($e.ts.ToString().Substring(0,[Math]::Min(16,$e.ts.ToString().Length))))"
    Write-Host ""
}
