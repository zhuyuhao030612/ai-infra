# local-agent 验证脚本
# 用法: pwsh -File verify.ps1
$ErrorActionPreference = "Continue"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$failures = 0

Write-Host "=== local-agent 验证 ==="
Write-Host ""

# 1. Lint (Ruff)
Write-Host "[1/3] Ruff check..."
Set-Location $ProjectDir
$ruff = & uv run ruff check app/ 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ 零错误"
} else {
    Write-Host "  ❌ Ruff 发现问题:"
    Write-Host $ruff
    $failures++
}

# 2. Python syntax check
Write-Host "[2/3] Python syntax..."
Get-ChildItem -Path "$ProjectDir\app" -Recurse -Include "*.py" | ForEach-Object {
    # Use forward slashes to avoid escape issues on Windows
    $pyPath = $_.FullName -replace '\\', '/'
    $result = & python -c "compile(open('$pyPath', encoding='utf-8').read(), '$($_.Name)', 'exec')" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ❌ $($_.Name): $result"
        $failures++
    }
}
if ($failures -eq 0) { Write-Host "  ✅ 语法通过" }

# 3. Health check (if server is running)
Write-Host "[3/3] Health check..."
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:9000/health" -UseBasicParsing -TimeoutSec 3
    if ($resp.StatusCode -eq 200) {
        Write-Host "  ✅ 服务在线"
    } else {
        Write-Host "  ⚠️ 服务返回 $($resp.StatusCode)"
    }
} catch {
    Write-Host "  ⚠️ 服务未运行（跳过）"
}

Write-Host ""
# Unified event log
& pwsh -File "D:\Code\ai-infra\scripts\log-event.ps1" -Type "verify.run" -Ok:$($failures -eq 0) -DataJson "{`"project`":`"local-agent`",`"failed`":$failures}"
if ($failures -eq 0) {
    Write-Host "=== 全部通过 ✅ ==="
    exit 0
} else {
    Write-Host "=== $failures 项失败 ❌ ==="
    exit 1
}
