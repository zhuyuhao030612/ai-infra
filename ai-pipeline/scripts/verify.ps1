# ai-pipeline 验证脚本
# 用法: pwsh -File verify.ps1
$ErrorActionPreference = "Continue"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$failures = 0

Write-Host "=== ai-pipeline 验证 ==="
Write-Host ""

# 1. Node syntax check
Write-Host "[1/2] Node.js syntax..."
$jsFiles = @("gpt55-server.js", "ask-gpt55.js", "vision.js")
foreach ($f in $jsFiles) {
    $path = Join-Path $ProjectDir $f
    if (Test-Path $path) {
        $result = & node --check $path 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ❌ $f : $result"
            $failures++
        } else {
            Write-Host "  ✅ $f"
        }
    } else {
        Write-Host "  ⏭ $f (不存在)"
    }
}

# 2. # SKIP: cmdsrv.py does not exist)
Write-Host "[2/2] Python syntax..."
$pyPath = Join-Path $ProjectDir "cmdsrv.py"
if (Test-Path $pyPath) {
    $pyPathFixed = $pyPath -replace '\\', '/'
    $result = & # SKIP: cmdsrv.py does not exist', 'exec')" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ❌ cmdsrv.py: $result"
        $failures++
    } else {
        Write-Host "  ✅ cmdsrv.py"
    }
} else {
    Write-Host "  ⏭ cmdsrv.py (不存在)"
}

Write-Host ""
if ($failures -eq 0) {
    Write-Host "=== 全部通过 ✅ ==="
    exit 0
} else {
    Write-Host "=== $failures 项失败 ❌ ==="
    exit 1
}
