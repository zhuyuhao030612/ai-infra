# 新任务初始化 —— 建立运行目录、复制模板
# 用法: pwsh -File new-run.ps1 -Task "修复 GPT-5.5 管道"
#       pwsh -File new-run.ps1 -Task "添加搜索功能" -Type "feature"
param(
    [Parameter(Mandatory=$true)]
    [string]$Task,
    [string]$Type = "task"  # task | feature | bugfix | review
)

$ErrorActionPreference = "Stop"
$CodeDir = "D:\Code"
$RunsDir = "$CodeDir\.ai-state\runs"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SafeName = $Task -replace '[\\/:*?"<>| ]', '-' -replace '-{2,}', '-' -replace '-$', ''
$SafeName = $SafeName.Substring(0, [Math]::Min(40, $SafeName.Length))
$RunDir = "$RunsDir\$Timestamp-$SafeName"

# Create run directory
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

# Task manifest
$manifest = @"
# $Task

## 元信息
- **ID**: $Timestamp
- **类型**: $Type
- **开始**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
- **状态**: 进行中

## 目标

## 影响范围

## 关键决策

## 执行记录

| 时间 | 步骤 | 结果 |
|------|------|------|

## 验证结果

## 经验教训
"@

$manifest | Out-File -FilePath "$RunDir\README.md" -Encoding UTF8

# Copy current-task template
$currentTask = @"
# Current Task

## 目标
$Task

## 当前阶段
初始化

## 运行目录
$RunDir

## 已完成
-

## 待完成
-

## 关键决策
-

## 风险
-
"@
$currentTask | Out-File -FilePath "$CodeDir\.ai-state\current-task.md" -Encoding UTF8

# Generate context-pack.md
$projectMap = if (Test-Path "$CodeDir\PROJECT_MAP.md") {
    (Get-Content "$CodeDir\PROJECT_MAP.md" -Raw) -split "`n" | Select-Object -First 20 | Out-String
} else { "(项目地图未找到)" }
$gitStatus = try { git -C $CodeDir status --short 2>$null | Out-String } catch { "(非 git 仓库)" }
$contextPack = @"
# Context Pack: $Task

**Run ID**: $Timestamp
**Type**: $Type
**Started**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Task
$Task

## Project Map (summary)
$projectMap

## Git Status
$gitStatus

## Recommended
1. lessons-search.ps1 -Task "$Task"
2. (if 3+ files) impact.ps1
3. verify.ps1
4. smoke/run-all.ps1

## Notes
(在此记录关键发现)
"@
$contextPack | Out-File -FilePath "$RunDir\context-pack.md" -Encoding UTF8

# Create task.json (machine-readable state)
$taskJson = [ordered]@{
    id = $Timestamp
    title = $Task
    prompt = $Task
    max_level = "L2"
    status = "running"
    created_at = (Get-Date -Format "o")
    schema_version = "1.0"
    evidence_path = "evidence.jsonl"
    run_dir = $RunDir
    transitions = @(
        @{from=$null; to="pending"; ts=(Get-Date -Format "o"); reason="Task created"}
        @{from="pending"; to="running"; ts=(Get-Date -Format "o"); reason="Run initialized"}
    )
}
$taskJson | ConvertTo-Json -Depth 5 | Out-File (Join-Path $RunDir "task.json") -Encoding UTF8

# Create empty evidence.jsonl
"# evidence.jsonl - one JSON object per tool call / evidence event" | Out-File (Join-Path $RunDir "evidence.jsonl") -Encoding UTF8

Write-Host "=== 新任务已初始化 ==="
Write-Host "运行目录: $RunDir"
Write-Host "任务文件: $RunDir\README.md"
Write-Host "状态文件: $CodeDir\.ai-state\current-task.md (已更新)"
Write-Host "机器状态: $RunDir\task.json"
Write-Host "证据日志: $RunDir\evidence.jsonl"
Write-Host ""
Write-Host "下一步:"
Write-Host "  1. pwsh -File $CodeDir\ai-infra\scripts\lessons-search.ps1 -Task `"$Task`""
Write-Host "  2. (若改 3+ 文件) pwsh -File $CodeDir\ai-infra\scripts\impact.ps1 -Files `"...`""
Write-Host "  3. 开始修改"
Write-Host "  4. pwsh -File $CodeDir\local-agent\scripts\verify.ps1"
Write-Host "  5. pwsh -File $CodeDir\ai-infra\smoke\run-all.ps1"
