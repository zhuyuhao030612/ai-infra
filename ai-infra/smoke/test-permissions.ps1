# L0-L5 permission enforcement tests — simulate pretool-guard inputs
# All tests are pure simulation, no actual dangerous operations
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$tests = 0; $failures = 0
$guardScript = "D:\Code\ai-infra\hooks\pretool-guard.ps1"

function Test-GuardDecision {
    param([string]$ToolName, [string]$InputStr, [string]$ExpectedDecision, [string]$TestDesc)
    $script:tests++
    Write-Host "[$tests] $TestDesc"
    $input = @{
        tool_name = $ToolName
        tool_input = $InputStr
    } | ConvertTo-Json -Compress
    $result = $input | & pwsh -NoLogo -NoProfile -File $guardScript 2>&1 | Out-String
    $decision = if ($result -match '"permissionDecision"\s*:\s*"(\w+)"') { $Matches[1] } else { "unknown" }
    if ($decision -eq $ExpectedDecision) {
        Write-Host "  ✅ $decision (expected)"
    } else {
        Write-Host "  ❌ Got '$decision', expected '$ExpectedDecision'"
        $script:failures++
    }
}

Write-Host "=== Permission Enforcement Tests (L0-L5) ==="
Write-Host ""

# Test 1: L0 — Read file (should allow)
Test-GuardDecision -ToolName "Read" -InputStr "D:\Code\CLAUDE.md" -ExpectedDecision "allow" -TestDesc "L0: Read file → allow"

# Test 2: L1 — Write within project (should allow)
Test-GuardDecision -ToolName "Write" -InputStr '{"file_path":"D:\Code\test-output.txt"}' -ExpectedDecision "allow" -TestDesc "L1: Write within project → allow"

# Test 3: L2 — Bash within project (should allow if safe)
Test-GuardDecision -ToolName "Bash" -InputStr "ls D:/Code/" -ExpectedDecision "allow" -TestDesc "L2: Safe Bash ls → allow"

# Test 4: L3 — Stop-Process without risk_ack (should deny)
Test-GuardDecision -ToolName "PowerShell" -InputStr "Stop-Process -Name notepad" -ExpectedDecision "deny" -TestDesc "L3: Stop-Process without risk_ack → deny"

# Test 5: L4 — Remove-Item Recurse (should deny)
Test-GuardDecision -ToolName "PowerShell" -InputStr "Remove-Item D:\Code\something -Recurse -Force" -ExpectedDecision "deny" -TestDesc "L4: Remove-Item -Recurse → deny"

# Test 6: L5 — Invoke-Expression (should deny)
Test-GuardDecision -ToolName "PowerShell" -InputStr 'Invoke-Expression "evil"' -ExpectedDecision "deny" -TestDesc "L5: Invoke-Expression → deny"

# Test 7: L4 — GitHub PAT pattern (should deny)
Test-GuardDecision -ToolName "Bash" -InputStr "ghp_1234567890abcdef1234567890abcdef123456" -ExpectedDecision "deny" -TestDesc "L4: GitHub PAT leak attempt → deny"

# Summary
Write-Host ""
Write-Host "════════════════════════"
$passed = $tests - $failures
Write-Host "  Permissions: $passed/$tests passed"
if ($failures -eq 0) {
    Write-Host "  🟢 L0-L5 enforcement working"
    exit 0
} else {
    Write-Host "  🔴 $failures enforcement gaps"
    exit 1
}
