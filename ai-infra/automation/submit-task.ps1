# Submit a task to the automation queue
param(
  [Parameter(Mandatory)][string]$Title,
  [Parameter(Mandatory)][string]$Prompt,
  [ValidateSet("L0","L1","L2","L3","L4","L5")][string]$MaxLevel="L2",
  [string]$DoneWhen="",
  [string]$VerifyBy="",
  [string]$FallbackIf=""
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$inbox = "D:\Code\ai-infra\tasks\inbox"
New-Item -ItemType Directory -Force -Path $inbox | Out-Null

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$taskId = "task-$ts-$([Guid]::NewGuid().ToString().Substring(0,6))"
$task = @{
  id = $taskId
  title = $Title
  prompt = $Prompt
  max_level = $MaxLevel
  allow_l3 = ($MaxLevel -in @("L3","L4","L5"))
  created_at = (Get-Date -Format "o")
  done_when = $DoneWhen
  verify_by = $VerifyBy
  fallback_if = $FallbackIf
  status = "pending"
  schema_version = "1.0"
  evidence_path = ""
  transitions = @(
    @{from=$null; to="pending"; ts=(Get-Date -Format "o"); reason="Task created"}
  )
} | ConvertTo-Json -Depth 5

$task | Out-File (Join-Path $inbox "$taskId.task.json") -Encoding UTF8
Write-Output $taskId
