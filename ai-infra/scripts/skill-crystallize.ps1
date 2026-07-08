# skill-crystallize.ps1 — Skill 结晶引擎（薄入口 → SelfLearn 模块）
param(
  [Parameter(Mandatory=$true)]
  [string]$TaskDescription,
  [string]$ExecutionLog,
  [string]$ExecutionLogFile,
  [string]$Outcome = "success",
  [string]$Model = "qwen2.5-coder:latest",
  [switch]$DryRun,
  [switch]$Force,
  [switch]$Json
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'lib') 'SelfLearn.psm1') -Force

$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$SkillsAutoDir = Join-Path (Join-Path $Root 'skills') '_auto'
$SkillsApprovedDir = Join-Path (Join-Path $Root 'skills') 'approved'

# Load execution log
if ($ExecutionLogFile -and (Test-Path $ExecutionLogFile)) {
  $ExecutionLog = Get-Content $ExecutionLogFile -Raw -Encoding UTF8
  Write-Host "[crystallize] Loaded execution log: $ExecutionLogFile"
}

# ── Phase 1: Complexity evaluation ──
Write-Host "[crystallize] Phase 1: Complexity evaluation..."
$keywords = @('WebSearch','WebFetch','Grep','Glob','Read','Write','Edit','Bash','PowerShell','Agent\(','Workflow\(','Skill\(')
$toolCallCount = 0
foreach ($kw in $keywords) { $toolCallCount += ([regex]::Matches($ExecutionLog, "(?i)$kw")).Count }
Write-Host "  Tool calls detected: ~$toolCallCount"

if ($toolCallCount -lt 5 -and -not $Force) {
  Write-Host "[crystallize] SKIP: too few tool calls (< 5). Use -Force."
  exit 0
}
if ($Outcome -ne "success" -and -not $Force) {
  Write-Host "[crystallize] SKIP: task did not succeed. Use -Force."
  exit 0
}

# ── Phase 2: Duplicate check ──
Write-Host "[crystallize] Phase 2: Duplicate check..."
$existingSkills = @()
foreach ($dir in @($SkillsApprovedDir, $SkillsAutoDir)) {
  if (Test-Path $dir) { $existingSkills += (Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue).Name }
}

# ── Phase 3-4: Reflect + Crystallize ──
Write-Host "[crystallize] Phase 3-4: Reflect + Crystallize via Ollama..."

$CrystallizePrompt = @"
You are a workflow crystallization agent. Analyze the task execution and produce a reusable SKILL.md.

## Task
$TaskDescription

## Execution Log
$ExecutionLog

## Outcome: $Outcome
## Existing skills (avoid duplicates): $($existingSkills -join ', ')

Crystallize into a SKILL.md. Make it GENERIC (use <placeholders> not specific values), ACTIONABLE (concrete tool+check+output per step), SELF-CONTAINED.

Output ONLY valid JSON:
{"crystallize":true,"skill_name":"slug","skill_description":"one-line","skill_content":"# name — description`n`n## When to use`n...`n`n## Steps`n### Step 1: Name`n- Tool: ...`n- Action: ...`n- Output: ...`n`n## Pitfalls`n- ...`n`n## Verification`n1. ...`n`n## Anti-patterns`n- ...","category":"workflow|security|debugging|devops","tags":["tag1","tag2"]}

If not worth crystallizing, set "crystallize":false with "reason".
"@

$extract = Invoke-OllamaExtract -Prompt $CrystallizePrompt -Model $Model -MaxTokens 8192 -TimeoutSec 180
if (-not $extract.Success) {
  Write-Error "[crystallize] Extraction failed: $($extract.Error)"
  exit 3
}
$result = $extract.ParsedObject

if (-not $result.crystallize) {
  Write-Host "[crystallize] SKIP: $($result.reason)"
  exit 0
}

# ── Dry run ──
if ($DryRun) {
  Write-Host "`n=== DRY RUN ==="
  Write-Host "Skill: $($result.skill_name) | Category: $($result.category)"
  Write-Host "--- Preview (500 chars) ---"
  Write-Host $result.skill_content.Substring(0, [Math]::Min(500, $result.skill_content.Length))
  Write-Host "---"
  exit 0
}

# ── Phase 5: Atomic write ──
Write-Host "[crystallize] Phase 5: Writing skill..."

$skillDir = Join-Path $SkillsAutoDir $result.skill_name
$skillFile = Join-Path $skillDir 'SKILL.md'
$skillMd = @"
---
name: $($result.skill_name)
description: $($result.skill_description)
version: 0.1.0
auto_generated: true
generated_date: $(Get-Date -Format 'yyyy-MM-dd')
category: $($result.category)
tags: [$($result.tags -join ', ')]
---

$($result.skill_content)
"@

$writeResult = Write-AtomicFile -TargetPath $skillFile -Content $skillMd -Source "crystallize:$($result.skill_name)"
if ($writeResult.Written) {
  # Also save execution trace
  $traceFile = Join-Path $skillDir '_execution-trace.md'
  $traceMd = "# Execution Trace — $($result.skill_name)`n`n**Date:** $(Get-Date) | **Calls:** ~$toolCallCount | **Outcome:** $Outcome`n`n$ExecutionLog"
  Write-AtomicFile -TargetPath $traceFile -Content $traceMd -Source "crystallize-trace:$($result.skill_name)" -SkipSecurity | Out-Null

  Write-Host "[crystallize] WROTE: skills/_auto/$($result.skill_name)/SKILL.md"
  Write-Host "  Review: move to skills/approved/ to activate"
} else {
  Write-Error "[crystallize] Write failed: $($writeResult.Error)"
  exit 4
}

if ($Json) { @{crystallized=$true; skill=$result.skill_name; category=$result.category} | ConvertTo-Json -Compress }
