# Run a single task — called by automation-worker
param([Parameter(Mandatory)][string]$TaskFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RootDir = Join-Path $env:AI_ROOT "D:\Code"
$task = Get-Content $TaskFile -Raw | ConvertFrom-Json
$taskId = $task.id
$runDir = "D:\Code\.ai-state\runs\$taskId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

# 1. Record start and run state transition
@{started_at=(Get-Date -Format "o");task=$taskId} | ConvertTo-Json | Out-File (Join-Path $runDir "start.json") -Encoding UTF8
& pwsh -File "D:\Code\ai-infra\scripts\state-transition.ps1" -TaskId $taskId -From "pending" -To "running" -Reason "Worker picked up task" 2>$null

# 2. Get mandatory steps from ai-start
$steps = & pwsh -NoLogo -NoProfile -File "D:\Code\ai-infra\scripts\ai-start.ps1" -Task $task.title -MachineReadable 2>&1
$steps | Out-File (Join-Path $runDir "plan.json") -Encoding UTF8

# 3. Build Claude prompt
$claudePrompt = @"
## 任务：$($task.title)
$($task.prompt)

## 约束
- 操作等级：最多 L2
- 禁止 L3+ 操作（删除/停止进程/SSH/curl/C盘写入/凭据读取）
- 完成后必须生成 handoff-summary
- 验证方法：$($task.verify_by)
- 回退方案：$($task.fallback_if)

## Skills 参考
- D:\Code\ai-infra\skills\USAGE_POLICY.md
- D:\Code\ai-infra\skills\handoff-summary-skill\SKILL.md
"@

# 4. Run Claude non-interactively
$resultFile = Join-Path $runDir "result.md"
Set-Content -Path $resultFile -Value "# Task Result: $taskId`n`nRunning..." -Encoding UTF8

try {
  claude -p $claudePrompt `
    --permission-mode dontAsk `
    --settings "D:\Code\.claude\settings.local.json" `
    --max-turns 15 `
    --allowedTools "Read, Bash(git:*)" `
    2>&1 | Out-File (Join-Path $runDir "claude-output.txt") -Encoding UTF8

  # 5. Check for stop signal
  $signalFile = "D:\Code\ai-infra\tasks\signals\$taskId.stopped"
  $stopped = Test-Path $signalFile

  if ($stopped) { Remove-Item $signalFile -Force -EA SilentlyContinue }

  # 6. Run verification — use Start-Process to avoid Invoke-Expression code injection (P0-2)
  # Only whitelisted verification commands are allowed; arguments are passed as literal strings
  $verifyOk = $true
  $allowedVerifiers = @(
    "Test-Path",
    "Select-String",
    "Get-Content",
    "python",
    "node",
    "pwsh",
    "powershell"
  )
  if ($task.verify_by) {
    $verifyCmd = $task.verify_by.Trim()
    $cmdName = ($verifyCmd -split '\s+')[0]
    if ($cmdName -notin $allowedVerifiers) {
      Write-Warning "verify_by command '$cmdName' is not in allowed verifiers whitelist; skipping verification"
      $verifyOk = $true
    } else {
      $cmdArgs = if ($verifyCmd -match '\s+') { $verifyCmd.Substring($verifyCmd.IndexOf(' ') + 1) } else { "" }
      try {
        if ($cmdArgs) {
          $vResult = & $cmdName @($cmdArgs -split '\s+') 2>&1
        } else {
          $vResult = & $cmdName 2>&1
        }
        $verifyOk = ($LASTEXITCODE -eq 0)
      } catch { $verifyOk = $false }
    }
  }

  # 7. Move to done or failed
  $outcome = if ($stopped -and $verifyOk) { "completed" } else { "failed" }
  & pwsh -File "D:\Code\ai-infra\scripts\state-transition.ps1" -TaskId $taskId -From "running" -To $outcome -Reason "verify=$verifyOk stopped=$stopped" 2>$null

  if ($stopped -and $verifyOk) {
    $dest = "D:\Code\ai-infra\tasks\done\$($taskId).done.json"
    @{ id=$taskId; status="done"; stopped=$stopped; verified=$verifyOk; finished_at=(Get-Date -Format "o") } | ConvertTo-Json | Out-File $dest -Encoding UTF8
  } else {
    $dest = "D:\Code\ai-infra\tasks\failed\$($taskId).failed.json"
    @{ id=$taskId; status="failed"; stopped=$stopped; verified=$verifyOk; finished_at=(Get-Date -Format "o") } | ConvertTo-Json | Out-File $dest -Encoding UTF8
  }

  Write-Output ($taskId + ": " + $(if($stopped -and $verifyOk){"done"}else{"failed"}))

} catch {
  $dest = "D:\Code\ai-infra\tasks\failed\$($taskId).failed.json"
  @{ id=$taskId; status="failed"; error=$_.Exception.Message; finished_at=(Get-Date -Format "o") } | ConvertTo-Json | Out-File $dest -Encoding UTF8
  Write-Output ($taskId + ": error")
}
