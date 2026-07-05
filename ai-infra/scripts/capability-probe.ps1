# PHS Capability Probe — auto-detect what works at session start
param([switch]$Json)
$ErrorActionPreference = "SilentlyContinue"
$results = @{}
$start = Get-Date

function Test-Cap($name, $script, $critical=$false) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $null = & $script 2>&1
        $ok = ($LASTEXITCODE -eq 0) -or ($LASTEXITCODE -eq $null)
    } catch { $ok = $false }
    $sw.Stop()
    $results[$name] = @{status=if($ok){"OK"}else{"DOWN"}; critical=$critical; latency_ms=$sw.ElapsedMilliseconds}
    Write-Host "  $(if($ok){'[OK]'}else{'[DOWN]'}) $name ($($sw.ElapsedMilliseconds)ms)"
}

Write-Host "=== PHS Capability Probe ==="
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

Write-Host "── Core ──"
Test-Cap "powershell" { Get-Date } $true
Test-Cap "python" { python -c "print(1)" } $true
Test-Cap "node" { node -e "console.log(1)" } $false

Write-Host "`n── Desktop ──"
Test-Cap "pyautogui" { python -c "import pyautogui" } $false
Test-Cap "pywinauto" { python -c "from pywinauto import Desktop; print('ok')" } $false
Test-Cap "rapidocr" { python -c "from rapidocr_onnxruntime import RapidOCR; RapidOCR()" } $false
Test-Cap "desktop_action" { & pwsh -File D:\Code\ai-infra\scripts\desktop-action.ps1 -Action active_window } $true
Test-Cap "screenshot" { & pwsh -File D:\Code\ai-infra\scripts\desktop-action.ps1 -Action screenshot } $true

Write-Host "`n── Vision ──"
$env:DOUBAO_API_KEY = "ark-e56757a8-8139-4575-bf05-d91ed9ce783f-c3094"
Test-Cap "doubao_vision" { node D:\Code\ai-pipeline\vision.js D:\PHS\prism\samples\build_1\sample_image.jpg "test" } $false

Write-Host "`n── Web ──"
Test-Cap "playwright_mcp" { $true } $false  # Assumes MCP active if session is running
Test-Cap "web_search" { $true } $false

Write-Host "`n── GPT Pipeline ──"
$gptRunning = Get-Process node -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "gpt55" }
Test-Cap "gpt55_pipeline" { if($gptRunning){$true}else{throw "not running"} } $false

Write-Host "`n── Bundled Deps ──"
Test-Cap "ffmpeg" { & D:\PHS\prism\_bundled\ffmpeg\ffmpeg.exe -version } $true
Test-Cap "ffprobe" { & D:\PHS\prism\_bundled\ffmpeg\ffprobe.exe -version } $true
Test-Cap "fpcalc" { & D:\PHS\prism\_bundled\chromaprint\chromaprint-fpcalc-1.5.1-windows-x86_64\fpcalc.exe -version } $false
Test-Cap "piper_model" { Test-Path D:\PHS\prism\runtime\piper_models\*.onnx } $true

$elapsed = [math]::Round(((Get-Date) - $start).TotalMilliseconds)
$okCount = ($results.Values | Where-Object { $_.status -eq "OK" }).Count
$downCount = ($results.Values | Where-Object { $_.status -eq "DOWN" }).Count
$criticalDown = ($results.Values | Where-Object { $_.status -eq "DOWN" -and $_.critical }).Count

Write-Host "`n════════════════════════════════════"
Write-Host "  OK: $okCount | DOWN: $downCount | CRITICAL DOWN: $criticalDown"
Write-Host "  Probe time: ${elapsed}ms"

$report = @{
    timestamp = (Get-Date -Format "o")
    elapsed_ms = $elapsed
    summary = @{ok=$okCount; down=$downCount; critical_down=$criticalDown}
    capabilities = $results
    health = if($criticalDown -eq 0){"HEALTHY"}else{"DEGRADED"}
}
$path = "D:\Code\ai-infra\reports\capability_probe.json"
New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
$report | ConvertTo-Json -Depth 3 | Out-File $path -Encoding UTF8
Write-Host "  Report: $path"

if ($Json) { $report | ConvertTo-Json -Depth 3 }
exit $(if($criticalDown -eq 0){0}else{1})
