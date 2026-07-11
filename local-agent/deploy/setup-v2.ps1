#Requires -Version 5.1
$ErrorActionPreference = "Stop"
param([switch]$DryRun)

$DeployDir = "D:\local-agent"
$Token = "mMfhSNBUo_Bn8ZPoGmyaG3CLUPhBRCP9G0iLNfha_ns"
$HrToken = "cXQgi2pSJBnkVvEjN4B3xSn4MOM7wJ4a88JLOFDZGMo"

function Step($name, $action) {
    Write-Host "[STEP] $name"
    if ($DryRun) { Write-Host "  DRY-RUN: skip"; return }
    & $action
    if ($LASTEXITCODE -ne 0) { throw "Step failed: $name" }
}

# 1. Install uv
Step "Install uv" {
    $installer = Join-Path $env:TEMP "uv-install.ps1"
    Invoke-WebRequest "https://github.com/astral-sh/uv/releases/latest/download/uv-installer.ps1" -OutFile $installer
    powershell -ExecutionPolicy Bypass -File $installer
}

# 2. Verify uv
$uvPath = Join-Path $env:USERPROFILE ".local\bin\uv.exe"
if (-not (Test-Path $uvPath)) { throw "uv install failed" }
Write-Host "  uv: OK"

# 3. Create dir + env
Step "Create env" {
    New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null
    $tokenLine = "AGENT_TOKEN=$Token"
    $hrLine = "HIGH_RISK_TOKEN=$HrToken"
    $envPath = Join-Path $DeployDir ".env"
    "$tokenLine`n$hrLine" | Out-File -FilePath $envPath -Encoding UTF8
}

# 4. Install deps
Step "Install deps" {
    Set-Location $DeployDir
    & $uvPath sync
}

# 5. Firewall
Step "Firewall" {
    netsh advfirewall firewall add rule name="Local Agent" dir=in action=allow protocol=TCP localport=9000
}

# 6. Start
Step "Start service" {
    Set-Location $DeployDir
    Start-Process -FilePath $uvPath -ArgumentList "run","uvicorn","app.main:app","--host","0.0.0.0","--port","9000" -WindowStyle Minimized
}

Write-Host ""
Write-Host "DONE. Health: http://localhost:9000/health"
Write-Host "Remote: http://$( (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -match 'Wi-Fi|WLAN|以太' -and $_.IPAddress -ne '127.0.0.1'} | Select-Object -First 1).IPAddress ):9000/"
