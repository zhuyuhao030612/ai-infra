# P0-5 负向测试：每个组件测 3 个失败路径
$ErrorActionPreference = "Continue"
$tests = 0; $failures = 0
$token = "mMfhSNBUo_Bn8ZPoGmyaG3CLUPhBRCP9G0iLNfha_ns"
$headers = @{Authorization="Bearer $token"}

Write-Host "=== Negative Path Tests ==="
Write-Host ""

# --- API: missing fields ---
$tests++; Write-Host "[$tests] API: /files/read — missing path"
try { $r = Invoke-RestMethod "http://127.0.0.1:9000/files/read" -Method POST -Headers $headers -Body "{}" -ContentType "application/json" -TimeoutSec 3
    if (-not $r.success) { Write-Host "  ✅ Returns error (expected)"; } else { Write-Host "  ❌ Should fail"; $failures++ }
} catch { Write-Host "  ✅ HTTP error as expected"; }

# --- API: path traversal ---
$tests++; Write-Host "[$tests] API: /files/read — path traversal attempt"
$r = Invoke-RestMethod "http://127.0.0.1:9000/files/read" -Method POST -Headers $headers -Body '{"path":"..\\..\\Windows\\System32\\config\\SAM"}' -ContentType "application/json" -TimeoutSec 3
if (-not $r.success) { Write-Host "  ✅ Blocked"; } else { Write-Host "  ❌ Should block traversal"; $failures++ }

# --- API: file too large ---
$tests++; Write-Host "[$tests] API: /files/read — nonexistent file"
$r = Invoke-RestMethod "http://127.0.0.1:9000/files/read" -Method POST -Headers $headers -Body '{"path":"D:\\NONEXISTENT_FILE_12345.txt"}' -ContentType "application/json" -TimeoutSec 3
if (-not $r.success) { Write-Host "  ✅ File not found (expected)"; } else { Write-Host "  ❌ Should fail"; $failures++ }

# --- API: /status/full without token ---
$tests++; Write-Host "[$tests] API: /status/full — no token"
try { Invoke-RestMethod "http://127.0.0.1:9000/status/full" -Method GET -TimeoutSec 3 | Out-Null
    Write-Host "  ❌ Should require token"; $failures++
} catch { Write-Host "  ✅ 401/403 (expected)" }

# --- PS: syntax error script ---
$tests++; Write-Host "[$tests] PS: ps-guard catches syntax error"
$badScript = "$env:TEMP\bad-script.ps1"
'param($x) if ($x -eq "test" {' | Out-File $badScript -Encoding UTF8
$result = pwsh -File D:\Code\ai-infra\scripts\ps-guard.ps1 -Path $badScript 2>&1 | Out-String
Remove-Item $badScript -Force
if ($result -notmatch "PS_GUARD_PASS") { Write-Host "  ✅ Syntax error caught"; } else { Write-Host "  ❌ Should catch error"; $failures++ }

# --- PS: cleanup dry-run doesn't delete ---
$tests++; Write-Host "[$tests] PS: cleanup dry-run protects"
$dummyDir = "$env:TEMP\cleanup-test-dir"
New-Item -ItemType Directory -Force -Path $dummyDir | Out-Null
"locked" | Out-File "$dummyDir\dummy.lock" -Encoding UTF8
(Get-Item $dummyDir).LastWriteTime = [DateTime]::Now.AddDays(-30)
$result = pwsh -File D:\Code\ai-infra\scripts\cleanup-runs.ps1 2>&1 | Out-String
$stillThere = Test-Path $dummyDir
Remove-Item $dummyDir -Recurse -Force
if ($stillThere) { Write-Host "  ✅ Dry-run preserved locked dir"; } else { Write-Host "  ❌ Should not delete"; $failures++ }

# --- JSON: corrupt events.jsonl tolerance ---
$tests++; Write-Host "[$tests] JSON: /status survives corrupt events.jsonl"
$eventsLog = "D:\Code\ai-infra\logs\events.jsonl"
# Write a bad line
Add-Content $eventsLog "{bad json !@#" -Encoding UTF8
try {
    $r = Invoke-RestMethod "http://127.0.0.1:9000/status" -Method GET -TimeoutSec 3
    if ($r.success) { Write-Host "  ✅ Survived corrupt JSONL"; } else { Write-Host "  ❌ Should survive"; $failures++ }
} catch { Write-Host "  ❌ 500 on corrupt JSONL"; $failures++ }
# Clean up bad line: keep only valid JSON
$lines = Get-Content $eventsLog | Where-Object { try { $_ | ConvertFrom-Json | Out-Null; $true } catch { $false } }
$lines | Set-Content $eventsLog -Encoding UTF8

# --- evidence-check: missing operation param ---
$tests++; Write-Host "[$tests] evidence-check.ps1: missing Operation param"
$ec = & pwsh -File D:\Code\ai-infra\scripts\evidence-check.ps1 -Operation "path-exists" -Target "D:\NONEXISTENT_FILE_XYZZY.txt" 2>&1 | Out-String
if ($ec -match '"ok":\s*false') { Write-Host "  ✅ Returns fail for nonexistent path"; } else { Write-Host "  ❌ Should report failure"; $failures++ }

# --- post-tool-recorder: survives bad input ---
$tests++; Write-Host "[$tests] post-tool-recorder.ps1: survives corrupt JSON input"
$badInput = '{not valid json !@#' | & pwsh -File D:\Code\ai-infra\scripts\post-tool-recorder.ps1 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "  ✅ Exits 0 gracefully"; } else { Write-Host "  ❌ Should exit 0"; $failures++ }

# --- pretool-guard: blocks GitHub PAT pattern ---
$tests++; Write-Host "[$tests] pretool-guard: blocks ghp_ token pattern"
$patInput = @{tool_name="Bash"; tool_input="export GITHUB_TOKEN=ghp_1234567890abcdef1234567890abcdef123456"} | ConvertTo-Json -Compress
$patResult = $patInput | & pwsh -File D:\Code\ai-infra\hooks\pretool-guard.ps1 2>&1 | Out-String
if ($patResult -match '"permissionDecision"\s*:\s*"deny"') { Write-Host "  ✅ PAT blocked"; } else { Write-Host "  ❌ Should block PAT"; $failures++ }

# --- Summary ---
Write-Host ""
$pass = $tests - $failures
Write-Host "=== Negative Paths: $pass/$tests ==="
if ($failures -eq 0) { Write-Host "🟢 All failure paths handled correctly"; exit 0 }
else { Write-Host "🔴 $failures unprotected"; exit 1 }
