# WiFi Win10 一键部署 local-agent
# 以管理员身份运行此脚本
param([string]$AgentToken = "mMfhSNBUo_Bn8ZPoGmyaG3CLUPhBRCP9G0iLNfha_ns")

$ErrorActionPreference = "Stop"
$DeployDir = "D:\local-agent"
$PythonVersion = "3.12.10"
$PythonInstaller = "python-$PythonVersion-amd64.exe"
$PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/$PythonInstaller"

Write-Host "========================================="
Write-Host "  Local Agent 一键部署"
Write-Host "========================================="
Write-Host ""

# 1. Check/Install Python
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }

if ($python) {
    $pyVer = & $python --version 2>&1
    Write-Host "[1/6] Python: $pyVer"
} else {
    Write-Host "[1/6] Python 未安装，正在下载..."
    Invoke-WebRequest $PythonUrl -OutFile "$env:TEMP\$PythonInstaller"
    Write-Host "  安装 Python (静默)..."
    Start-Process -FilePath "$env:TEMP\$PythonInstaller" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "  Python 安装完成"
}

# 2. Install uv
Write-Host "[2/6] 安装 uv..."
$uv = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uv) {
    Invoke-WebRequest "https://github.com/astral-sh/uv/releases/latest/download/uv-installer.ps1" -OutFile "$env:TEMP\uv-install.ps1"
    & "$env:TEMP\uv-install.ps1"
    $env:Path += ";$env:USERPROFILE\.local\bin"
}
uv --version

# 3. Create project directory + copy files
Write-Host "[3/6] 部署 local-agent 到 $DeployDir..."
if (-not (Test-Path $DeployDir)) { New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null }

# Copy from current directory (the deploy folder is alongside the setup script)
$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentDir = Split-Path -Parent $sourceDir

Copy-Item "$parentDir\app" -Destination $DeployDir -Recurse -Force
Copy-Item "$parentDir\pyproject.toml" -Destination $DeployDir -Force
Copy-Item "$parentDir\scripts" -Destination $DeployDir -Recurse -Force

# Create .env
@"
AGENT_TOKEN=$AgentToken
HIGH_RISK_TOKEN=cXQgi2pSJBnkVvEjN4B3xSn4MOM7wJ4a88JLOFDZGMo
"@ | Out-File "$DeployDir\.env" -Encoding UTF8

Write-Host "  文件已复制"

# 4. Install dependencies
Write-Host "[4/6] 安装 Python 依赖..."
Set-Location $DeployDir
uv sync
Write-Host "  依赖安装完成"

# 5. Firewall rule
Write-Host "[5/6] 配置防火墙..."
try {
    netsh advfirewall firewall add rule name="Local Agent" dir=in action=allow protocol=TCP localport=9000
    Write-Host "  防火墙规则已添加"
} catch {
    Write-Host "  防火墙配置失败（可能已存在或权限不足）: $_"
}

# 6. Start + auto-start
Write-Host "[6/6] 启动服务..."
$watchdogScript = "$DeployDir\scripts\watchdog.ps1"
$startScript = "$DeployDir\scripts\start.ps1"

# Start now
Start-Process -FilePath "pwsh" -ArgumentList "-NoLogo -WindowStyle Hidden -File `"$watchdogScript`"" -WindowStyle Hidden

# Add to Startup folder
$startupDir = [Environment]::GetFolderPath('Startup')
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$startupDir\LocalAgentWatchdog.lnk")
$Shortcut.TargetPath = "pwsh"
$Shortcut.Arguments = "-NoLogo -WindowStyle Hidden -File `"$watchdogScript`""
$Shortcut.WindowStyle = 7
$Shortcut.Save()

Write-Host ""
Write-Host "========================================="
Write-Host "  ✅ Local Agent 部署完成"
Write-Host "  端口: 9000"
Write-Host "  健康检查: http://127.0.0.1:9000/health"
Write-Host "  Web UI: http://127.0.0.1:9000/"
Write-Host "  IP: $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -match 'Wi-Fi|WLAN|以太'}).IPAddress)"
Write-Host "========================================="
