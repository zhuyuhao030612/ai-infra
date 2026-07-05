#requires -Version 5.1
<# Task router: reads agent-router.json, classifies task, outputs capability plan.
   Usage: pwsh -File route-task.ps1 -Task "描述" [-Json] #>
param([Parameter(Mandatory=$true)][string]$Task, [switch]$Json)

$ErrorActionPreference = "Continue"
$root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { "D:\Code" }
$routerPath = Join-Path $root ".claude\agent-router.json"

if (-not (Test-Path $routerPath)) {
    $err = @{ok=$false;error="agent-router.json not found"}
    if ($Json) { $err | ConvertTo-Json } else { Write-Host "ERROR: $routerPath not found" }
    exit 1
}

$router = Get-Content $routerPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Classify task type (if-elseif chain: highest risk first)
$taskType = "simple_edit"
$riskLevel = "L1"
if ($Task -match '(?i)删除|重置|清空|production|生产|delete.*all|wipe') { $taskType = "destructive"; $riskLevel = "L5" }
elseif ($Task -match '(?i)密钥|远程|部署|SSH|deploy|remote|安全|审计|漏洞|注入|token|secret|凭证|security|audit|vuln') { $taskType = "security_audit"; $riskLevel = "L4" }
elseif ($Task -match '(?i)hook|门禁|gate|stop-gate|block-dangerous|recorder') { $taskType = "hook_or_gate"; $riskLevel = "L3" }
elseif ($Task -match '(?i)重构|多文件|multi.?file|重写|架构|设计|refactor|rewrite|architect') { $taskType = "multi_file_refactor"; $riskLevel = "L2" }
elseif ($Task -match '(?i)复杂|算法|实现|功能|feature|implement|complex') { $taskType = "complex_code"; $riskLevel = "L2" }
elseif ($Task -match '(?i)截图|看屏幕|视觉|OCR|图片|画面|screenshot') { $taskType = "vision_screenshot" }
elseif ($Task -match '(?i)浏览器|网页|URL|表单|browser|webpage') { $taskType = "browser_web" }
elseif ($Task -match '(?i)桌面|窗口|点击|GUI|desktop|click|button') { $taskType = "desktop_gui" }
elseif ($Task -match '(?i)大文件|日志|长文本|review.*log|large.*context') { $taskType = "large_context_review" }
elseif ($Task -match '(?i)json|修复|正则|提取|小改|fix.*json|regex') { $taskType = "json_fix" }

$route = if ($router.routes.PSObject.Properties.Name -contains $taskType) { $router.routes.$taskType } else { $router.routes.simple_edit }
$risk = if ($router.riskLevels.PSObject.Properties.Name -contains $riskLevel) { $router.riskLevels.$riskLevel } else { $router.riskLevels.L0 }

$plan = [pscustomobject]@{
    ok = $true
    task = $Task
    task_type = $taskType
    risk_level = $riskLevel
    primary_agent = $route.primary
    tool = $route.tool
    timeout_sec = $route.timeout
    required_checks = @($risk.require)
    required_evidence = @("modified_files", "test_results", "final-report")
    generated_at = (Get-Date -Format 'o')
}

$planPath = Join-Path $root ".claude\run-state\capability-plan.json"
$planDir = Split-Path -Parent $planPath
New-Item -ItemType Directory -Force -Path $planDir | Out-Null
$plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $planPath -Encoding UTF8

if ($Json) {
    $plan | ConvertTo-Json -Depth 6
} else {
    Write-Host "=== Task Route ==="
    Write-Host "Type: $taskType | Risk: $riskLevel | Agent: $($route.primary)"
    Write-Host "Tool: $($route.tool) | Timeout: $($route.timeout_sec)s"
    Write-Host "Checks: $($risk.require -join ', ')"
    Write-Host "Plan: $planPath"
}
exit 0
