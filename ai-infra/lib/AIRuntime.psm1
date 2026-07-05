Set-StrictMode -Version Latest

function Assert-AIRunContext {
    [CmdletBinding()]
    param()

    if ($env:AI_ORCHESTRATED -ne '1') {
        throw "AI Runtime 上下文检查失败：当前脚本未通过统一入口 ai.ps1 调用。请使用: ai exec <command> [arguments]"
    }

    return $true
}

function Assert-AIGuard {
    [CmdletBinding()]
    param(
        [ValidateSet('destructive', 'sensitive', 'normal')]
        [string]$RiskLevel = 'normal'
    )

    Assert-AIRunContext | Out-Null

    if ($RiskLevel -eq 'destructive' -and $env:AI_GUARD_PASSED -ne '1') {
        throw "AI 安全守卫检查失败：destructive 级别操作必须先通过安全守卫。请通过 ai.ps1 执行并完成危险操作确认。"
    }

    return $true
}

function Assert-PreflightGate {
    [CmdletBinding()]
    param()
    # Read preflight state from file (cross-process, survives new pwsh shells)
    $stateFile = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime') 'preflight-state.json'
    if (-not (Test-Path $stateFile)) {
        throw "AI Preflight 门禁失败：缺少 preflight 状态文件。请先运行: ai preflight '<任务描述>'"
    }
    try {
        $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "AI Preflight 门禁失败：状态文件损坏。请重新运行: ai preflight '<任务描述>'"
    }
    if ([string]::IsNullOrWhiteSpace($state.token)) {
        throw "AI Preflight 门禁失败：缺少 token。请先运行: ai preflight '<任务描述>'"
    }
    $ts = 0
    if (-not [long]::TryParse($state.timestamp, [ref]$ts)) {
        throw "AI Preflight 门禁失败：时间戳无效。请重新运行: ai preflight '<任务描述>'"
    }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $age = $now - $ts
    if ($age -lt 0 -or $age -gt 1800) {
        throw "AI Preflight 门禁失败：preflight 已过期（${age}s，限1800s）。请重新运行: ai preflight '<任务描述>'"
    }
    return $true
}

Export-ModuleMember -Function Assert-AIRunContext, Assert-PreflightGate, Assert-AIGuard
