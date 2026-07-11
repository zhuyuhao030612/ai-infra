# Task planner — decompose big tasks into subtask JSONs
param(
  [Parameter(Mandatory)][string]$Title,
  [Parameter(Mandatory)][string]$Prompt,
  [ValidateSet("L0","L1","L2")][string]$MaxLevel="L2",
  [switch]$AutoSubmit
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$inbox = "D:\Code\ai-infra\tasks\inbox"
New-Item -ItemType Directory -Force -Path $inbox | Out-Null

# Simple decomposition: plan → implement → verify → handoff
$subtasks = @(
  @{title="$Title - 规划";prompt="规划 $Prompt 。分析影响范围，输出步骤清单。";level="L1"},
  @{title="$Title - 执行";prompt="执行：$Prompt 。严格按规划步骤，每次只改一个文件，每步验证。禁止 L3+。";level=$MaxLevel},
  @{title="$Title - 验证";prompt="验证：$Prompt 已完成。检查语法/测试/smoke。如有失败，生成 failure-analysis。";level="L1"},
  @{title="$Title - 总结";prompt="总结：$Prompt 。生成 handoff 报告。";level="L1"}
)

$ids = @()
foreach ($st in $subtasks) {
  if ($AutoSubmit) {
    $id = & "D:\Code\ai-infra\automation\submit-task.ps1" `
      -Title $st.title -Prompt $st.prompt -MaxLevel $st.level `
      -DoneWhen "目标达成且验证通过" `
      -VerifyBy "node --check D:\Code\ai-pipeline\gpt55-server.js; node --check D:\Code\ai-pipeline\gpt55-artifacts.js" `
      -FallbackIf "失败则生成 failure-analysis 并通知老板"
    $ids += $id
  } else {
    Write-Host "Plan: $($st.title) (L$($st.level))"
  }
}

if ($AutoSubmit) { Write-Host "Submitted: $($ids.Count) tasks" }
else { Write-Host "Run with -AutoSubmit to queue these tasks" }
