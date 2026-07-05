# security-gate.ps1 — 安全扫描门禁（薄入口 → SelfLearn 模块）
param(
  [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
  [string]$Content,
  [string]$Source = "manual",
  [switch]$Json,
  [switch]$VerboseOutput
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'lib') 'SelfLearn.psm1') -Force

$result = Test-SecurityThreat -Content $Content -Source $Source

if ($Json) {
  @{
    passed = $result.Passed
    blocked = $result.HasP0
    finding_count = $result.FindingCount
    p0_count = $result.P0Count
    p1_count = $result.P1Count
    p2_count = $result.P2Count
    findings = @($result.Findings | Select-Object Severity, Category, Description, Match, Context)
    source = $Source
  } | ConvertTo-Json -Depth 5 -Compress
  exit $(if($result.HasP0){1}else{0})
}

if ($VerboseOutput) {
  Write-Host "`n=== SECURITY GATE ==="
  Write-Host "Source: $Source | Length: $($Content.Length) | Findings: $($result.FindingCount)"
  foreach ($f in $result.Findings) {
    Write-Host "  [$($f.Severity)] $($f.Category): $($f.Description)"
    Write-Host "    Match: $($f.Match)"
  }
}

if ($result.HasP0) {
  Write-Host "[SECURITY GATE] BLOCKED — $($result.P0Count) P0 threat(s)"
  Write-Host "  Review findings and sanitize before retrying."
  exit 1
} else {
  if ($result.FindingCount -gt 0) {
    Write-Host "[SECURITY GATE] WARNING — $($result.FindingCount) non-P0 finding(s). Review advised."
  } elseif ($VerboseOutput) {
    Write-Host "[SECURITY GATE] PASS"
  }
  exit 0
}
