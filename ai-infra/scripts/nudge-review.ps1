# nudge-review.ps1 — Nudge 引擎（薄入口 → SelfLearn 模块）
param(
  [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
  [string]$SessionDescription,
  [string]$Model = "qwen2.5-coder:latest",
  [switch]$DryRun,
  [switch]$Json
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'lib') 'SelfLearn.psm1') -Force

$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$MemoryDir = Join-Path (Join-Path $Root '..') 'memory'
$SkillsAutoDir = Join-Path (Join-Path $Root 'skills') '_auto'
$MemIndexFile = Join-Path (Join-Path $Root '..') 'MEMORY.md'

# ── Prompt 模板（业务层资产，留在入口脚本）──
$ReviewPrompt = @"
You are a knowledge extraction agent. Review the session description and extract:

1. **Memories** — durable facts. Each: name (kebab-case), description (one-line), type (user|feedback|project|reference), content (with Why/How-to-apply for feedback/project).

2. **Skills** — if complex multi-step workflow completed, crystallize into reusable SKILL.md. Each: name (slug), description, content (sections: When to use, Steps, Pitfalls, Verification).

3. **Pitfalls** — mistakes made, to add to existing skills.

Rules: skip trivial/obvious. Quality > quantity (1-3 memories max). Output ONLY valid JSON.

Session:
---
$SessionDescription
---

Output: {"memories":[{...}],"skills":[{...}],"pitfalls":[{...}],"keep":true}
"@

# ── Phase 1: Ollama 抽取 ──
Write-Host "[nudge] Extracting via Ollama..."
$extract = Invoke-OllamaExtract -Prompt $ReviewPrompt -Model $Model -MaxTokens 4096
if (-not $extract.Success) {
  Write-Error "[nudge] Extraction failed: $($extract.Error)"
  exit 2
}
$result = $extract.ParsedObject
Write-Host "[nudge] Extracted: $($result.memories.Count) memories, $($result.skills.Count) skills, $($result.pitfalls.Count) pitfalls"

if (-not $result.keep) {
  Write-Host "[nudge] Nothing worth saving."
  exit 0
}

# ── Phase 2: Dry run ──
if ($DryRun) {
  Write-Host "`n=== DRY RUN ==="
  Write-Host "`n[Memories]"
  foreach ($m in $result.memories) { Write-Host "  - $($m.name): $($m.description)" }
  Write-Host "`n[Skills]"
  foreach ($s in $result.skills) { Write-Host "  - $($s.name): $($s.description)" }
  Write-Host "`n[Pitfalls]"
  foreach ($p in $result.pitfalls) { Write-Host "  - $($p.skill_name): $($p.pitfall)" }
  exit 0
}

# ── Phase 3: 写入记忆（通过原子写入+安全门禁）──
$newMemories = @()
foreach ($m in $result.memories) {
  $memFile = Join-Path $MemoryDir "$($m.name).md"
  if (Test-Path $memFile) {
    Write-Host "[nudge] SKIP (exists): $($m.name)"
    continue
  }

  $type = if ($m.type -match '^(user|feedback|project|reference)$') { $m.type } else { 'reference' }
  $frontmatter = @"
---
name: $($m.name)
description: $($m.description)
metadata:
  type: $type
---

$($m.content)
"@

  $writeResult = Write-AtomicFile -TargetPath $memFile -Content $frontmatter -Source "nudge:$($m.name)"
  if ($writeResult.Written) {
    Write-Host "[nudge] WROTE memory: $($m.name)"
    $newMemories += $m
  } else {
    Write-Host "[nudge] BLOCKED: $($m.name) — $($writeResult.Error)"
  }
}

# ── Phase 4: 更新索引 ──
if ($newMemories.Count -gt 0 -and (Test-Path $MemIndexFile)) {
  $indexContent = [System.IO.File]::ReadAllText($MemIndexFile)
  foreach ($m in $newMemories) {
    $hook = if ($m.content.Length -gt 80) { ($m.content.Substring(0, 80) -replace "`n",' ') + '...' } else { $m.content -replace "`n",' ' }
    $line = "- [$($m.name)](memory/$($m.name).md) — $hook"
    if ($indexContent -notmatch [regex]::Escape($m.name)) {
      $indexContent += "`n$line"
    }
  }
  Write-AtomicFile -TargetPath $MemIndexFile -Content $indexContent -Source "nudge:mem-index" -SkipSecurity | Out-Null
  Write-Host "[nudge] Updated MEMORY.md index"
}

# ── Phase 5: 写入技能 ──
foreach ($s in $result.skills) {
  $skillDir = Join-Path $SkillsAutoDir $s.name
  $skillFile = Join-Path $skillDir 'SKILL.md'
  $skillContent = @"
---
name: $($s.name)
description: $($s.description)
version: 0.1.0
auto_generated: true
generated_date: $(Get-Date -Format 'yyyy-MM-dd')
---
$($s.content)
"@
  $writeResult = Write-AtomicFile -TargetPath $skillFile -Content $skillContent -Source "nudge-skill:$($s.name)"
  if ($writeResult.Written) {
    Write-Host "[nudge] WROTE skill: $($s.name)"
  } else {
    Write-Host "[nudge] BLOCKED: $($s.name) — $($writeResult.Error)"
  }
}

# ── Phase 6: 追加 pitfalls ──
foreach ($p in $result.pitfalls) {
  $skillDirs = @((Join-Path (Join-Path $Root 'skills') 'approved'), $SkillsAutoDir)
  foreach ($baseDir in $skillDirs) {
    $existingDir = Get-ChildItem $baseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $p.skill_name } | Select-Object -First 1
    if ($existingDir) {
      $existingFile = Join-Path $existingDir.FullName 'SKILL.md'
      $content = [System.IO.File]::ReadAllText($existingFile)
      $newPitfall = "`n- $($p.pitfall)"
      if ($content -notmatch [regex]::Escape($p.pitfall)) {
        $content += $newPitfall
        Write-AtomicFile -TargetPath $existingFile -Content $content -Source "nudge-pitfall:$($p.skill_name)" -SkipSecurity | Out-Null
        Write-Host "[nudge] Added pitfall to: $($p.skill_name)"
      }
      break
    }
  }
}

Write-Host "`n[nudge] DONE — m:$($newMemories.Count) s:$($result.skills.Count) p:$($result.pitfalls.Count)"
if ($Json) { @{memories=$newMemories.Count; skills=$result.skills.Count; pitfalls=$result.pitfalls.Count} | ConvertTo-Json -Compress }
