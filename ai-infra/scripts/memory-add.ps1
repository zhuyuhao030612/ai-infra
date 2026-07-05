# 结构化记忆 — 可检索，不只是 markdown
param([Parameter(Mandatory=$true)][string]$Type, [Parameter(Mandatory=$true)][string]$Summary, [string[]]$Keywords=@(), [string]$Decision="", [string]$Evidence="")

$MemoryDir = "D:\Code\ai-infra\memory"
New-Item -ItemType Directory -Force -Path $MemoryDir | Out-Null

$entry = [ordered]@{
    ts = (Get-Date -Format "o")
    type = $Type  # failure, decision, fact, command, insight
    topic = $Keywords
    summary = $Summary
    decision = $Decision
    evidence = $Evidence
} | ConvertTo-Json -Compress

Add-Content -Path "$MemoryDir\sessions.jsonl" -Value $entry

# Also write to decisions or failures for quick lookup
if ($Type -eq "decision" -and $Decision) { Add-Content -Path "$MemoryDir\decisions.jsonl" -Value $entry }
if ($Type -eq "failure") { Add-Content -Path "$MemoryDir\failures.jsonl" -Value $entry }

Write-Host "[memory] Added: $Type — $Summary"
