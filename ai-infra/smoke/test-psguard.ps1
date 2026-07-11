# ps-guard edge case tests — verify the guard catches what it should
param()
$ErrorActionPreference = "Continue"
$tests = 0; $failures = 0
$guardScript = "D:\Code\ai-infra\scripts\ps-guard.ps1"
$tempDir = Join-Path $env:TEMP "psguard-tests"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

Write-Host "=== PS Guard Edge Case Tests ==="
Write-Host ""

# Test 1: Valid script passes
$tests++
Write-Host "[$tests] Valid clean script → PASS"
$valid = Join-Path $tempDir "valid.ps1"
@'
param([string]$Name)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Write-Host "Hello $Name"
'@ | Out-File $valid -Encoding UTF8
$result = & pwsh -File $guardScript -Path $valid 2>&1 | Out-String
if ($result -match "PS_GUARD_PASS") { Write-Host "  ✅ PASS" } else { Write-Host "  ❌ Should pass"; $failures++ }

# Test 2: Missing StrictMode → WARN
$tests++
Write-Host "[$tests] Missing StrictMode → WARN"
$missingSM = Join-Path $tempDir "missing-sm.ps1"
@'
$ErrorActionPreference = "Stop"
Write-Host "No StrictMode"
'@ | Out-File $missingSM -Encoding UTF8
$result = & pwsh -File $guardScript -Path $missingSM 2>&1 | Out-String
if ($result -match "warnings=1" -or $result -match "WARN") { Write-Host "  ✅ Warned" } else { Write-Host "  ❌ Should warn about missing StrictMode"; $failures++ }

# Test 3: Invoke-Expression → FAIL
$tests++
Write-Host "[$tests] Invoke-Expression → FAIL"
$hasIex = Join-Path $tempDir "has-iex.ps1"
@'
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Invoke-Expression "Write-Host bad"
'@ | Out-File $hasIex -Encoding UTF8
$result = & pwsh -File $guardScript -Path $hasIex 2>&1 | Out-String
if ($result -match "PS_GUARD_FAIL" -or $LASTEXITCODE -ne 0) { Write-Host "  ✅ FAIL (caught iex)" } else { Write-Host "  ❌ Should fail"; $failures++ }

# Test 4: Hardcoded C: drive path → FAIL
$tests++
Write-Host "[$tests] Hardcoded C:\ path → FAIL"
$hasCPath = Join-Path $tempDir "has-cpath.ps1"
@'
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$path = "C:\Windows\System32"
'@ | Out-File $hasCPath -Encoding UTF8
$result = & pwsh -File $guardScript -Path $hasCPath 2>&1 | Out-String
if ($result -match "PS_GUARD_FAIL" -or $LASTEXITCODE -ne 0) { Write-Host "  ✅ FAIL (caught C:\ path)" } else { Write-Host "  ❌ Should fail"; $failures++ }

# Test 5: Bearer token in string → FAIL
$tests++
Write-Host "[$tests] Bearer token literal → FAIL"
$hasToken = Join-Path $tempDir "has-token.ps1"
@'
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$headers = @{Authorization="Bearer sk-1234567890abcdef1234567890abcdef"}
'@ | Out-File $hasToken -Encoding UTF8
$result = & pwsh -File $guardScript -Path $hasToken 2>&1 | Out-String
if ($result -match "PS_GUARD_FAIL" -or $LASTEXITCODE -ne 0) { Write-Host "  ✅ FAIL (caught token)" } else { Write-Host "  ❌ Should fail"; $failures++ }

# Test 6: risk_ack=true in script → FAIL
$tests++
Write-Host "[$tests] risk_ack=true → FAIL"
$hasRiskAck = Join-Path $tempDir "has-riskack.ps1"
@'
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$risk_ack = $true
'@ | Out-File $hasRiskAck -Encoding UTF8
$result = & pwsh -File $guardScript -Path $hasRiskAck 2>&1 | Out-String
if ($result -match "PS_GUARD_FAIL" -or $LASTEXITCODE -ne 0) { Write-Host "  ✅ FAIL (caught risk_ack)" } else { Write-Host "  ❌ Should fail"; $failures++ }

# Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# Summary
Write-Host ""
Write-Host "════════════════════════"
$passed = $tests - $failures
Write-Host "  PS Guard: $passed/$tests passed"
if ($failures -eq 0) {
    Write-Host "  🟢 All edge cases handled"
    exit 0
} else {
    Write-Host "  🔴 $failures gaps"
    exit 1
}
