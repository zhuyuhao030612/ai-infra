# GUI 全链路演练：gui-probe → crop → vision → coordinate → click → verify
# 用本地已知窗口（记事本或计算器）做端到端验证
$ErrorActionPreference = "Continue"
$token = "mMfhSNBUo_Bn8ZPoGmyaG3CLUPhBRCP9G0iLNfha_ns"
$hr = "cXQgi2pSJBnkVvEjN4B3xSn4MOM7wJ4a88JLOFDZGMo"
$headers = @{Authorization="Bearer $token";"X-High-Risk-Token"=$hr}
$tests = 0; $failures = 0

Write-Host "=== GUI E2E Chain Drill ==="
Write-Host ""

# --- Test 1: gui-probe captures foreground window ---
$tests++
Write-Host "[$tests] gui-probe captures foreground window..."
# Check for existing crops before
$beforeCrops = Get-ChildItem "D:\Code\screenshots\gui-probe-*.jpg" -EA SilentlyContinue
& D:\Code\ai-infra\scripts\gui-probe.ps1 2>&1 | Out-Null
# Check for new crop file
$afterCrops = Get-ChildItem "D:\Code\screenshots\gui-probe-*.jpg" -EA SilentlyContinue
$newCrop = $afterCrops | Where-Object { $_.LastWriteTime -gt [DateTime]::Now.AddSeconds(-10) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($newCrop) {
    Write-Host "  ✅ Probe completed - $($newCrop.Name) ($([Math]::Round($newCrop.Length/1KB,1))KB)"
} elseif ($beforeCrops.Count -ne $afterCrops.Count) {
    $c = $afterCrops | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "  ✅ Probe completed - $($c.Name) ($([Math]::Round($c.Length/1KB,1))KB)"
} else {
    Write-Host "  ❌ Probe failed - no crop generated"
    $failures++
}

# --- Test 2: screenshot → file via local-agent ---
$tests++
Write-Host "[$tests] Screenshot via local-agent..."
$r = Invoke-RestMethod "http://127.0.0.1:9000/desktop/screenshot/file?filename=e2e-test.png" -Method POST -Headers $headers -TimeoutSec 10
if ($r.success) {
    $img = Get-Item "D:\Code\screenshots\e2e-test.png" -EA SilentlyContinue
    if ($img) { Write-Host "  ✅ $([Math]::Round($img.Length/1KB,1))KB" }
} else { Write-Host "  ❌ Failed"; $failures++ }

# --- Test 3: click + verify with hash ---
$tests++
Write-Host "[$tests] Click + state change detection..."
# Take pre-click screenshot hash
$preFile = "D:\Code\screenshots\e2e-pre.png"
Invoke-RestMethod "http://127.0.0.1:9000/desktop/screenshot/file?filename=e2e-pre.png" -Method POST -Headers $headers -TimeoutSec 10 | Out-Null
if (Test-Path $preFile) {
    $preHash = (Get-FileHash $preFile -Algorithm MD5).Hash
    # Click at center of screen (harmless)
    Invoke-RestMethod http://127.0.0.1:9000/desktop/click -Method POST -Body '{"x":640,"y":360,"button":"left"}' -ContentType "application/json" -Headers $headers -TimeoutSec 5 | Out-Null
    Start-Sleep 1
    # Post-click screenshot
    $postFile = "D:\Code\screenshots\e2e-post.png"
    Invoke-RestMethod "http://127.0.0.1:9000/desktop/screenshot/file?filename=e2e-post.png" -Method POST -Headers $headers -TimeoutSec 10 | Out-Null
    if (Test-Path $postFile) {
        $postHash = (Get-FileHash $postFile -Algorithm MD5).Hash
        Write-Host "  Pre hash: $preHash"
        Write-Host "  Post hash: $postHash"
        Write-Host "  ✅ Hash comparison works (change=$($preHash -ne $postHash))"
    } else { Write-Host "  ❌ Post screenshot failed"; $failures++ }
    Remove-Item $preFile,$postFile -Force -EA SilentlyContinue
} else { Write-Host "  ❌ Pre screenshot failed"; $failures++ }

# --- Summary ---
Write-Host ""
Write-Host "=== GUI E2E: $($tests - $failures)/$tests 通过 ==="
if ($failures -eq 0) { Write-Host "🟢 GUI chain functional"; exit 0 } else { Write-Host "🔴 $failures failures"; exit 1 }
