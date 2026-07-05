# skill-patch.ps1 — Skill 自修复（薄入口 → SelfLearn 模块）
param(
  [Parameter(Mandatory=$true)][string]$SkillName,
  [Parameter(Mandatory=$true)][string]$Correction,
  [string]$Model = "qwen2.5-coder:latest",
  [switch]$DryRun, [switch]$Force, [switch]$Json
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'lib') 'SelfLearn.psm1') -Force

$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$SkillsAutoDir = Join-Path (Join-Path $Root 'skills') '_auto'
$SkillsApprovedDir = Join-Path (Join-Path $Root 'skills') 'approved'
$SkillsTopDir = Join-Path $Root 'skills'

# ── 1. Find skill ──
$skillFile = $null; $skillSource = ''
foreach ($baseDir in @($SkillsApprovedDir, $SkillsAutoDir, $SkillsTopDir)) {
  $dir = Get-ChildItem $baseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $SkillName } | Select-Object -First 1
  if ($dir) {
    $candidate = Join-Path $dir.FullName 'SKILL.md'
    if (Test-Path $candidate) { $skillFile = $candidate; $skillSource = $baseDir; break }
  }
}
if (-not $skillFile) {
  Write-Error "Skill not found: $SkillName"
  Get-ChildItem $SkillsApprovedDir,$SkillsAutoDir,$SkillsTopDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  - $($_.Name)" }
  exit 1
}
Write-Host "[patch] Found: $SkillName"
$originalContent = [System.IO.File]::ReadAllText($skillFile)

# ── 2. Analyze via Ollama ──
Write-Host "[patch] Analyzing correction..."
$PatchPrompt = @"
You are a skill maintenance agent. Given a SKILL.md and a correction request, identify the EXACT section to fix.

## SKILL.md
$originalContent

## Correction
$Correction

Output ONLY valid JSON:
{"patch":true,"section_name":"Step 3: Foo","find_text":"exact text to find","replace_text":"replacement text","reason":"why"}
If correction doesn't apply, set "patch":false with "reason".
"@

$extract = Invoke-OllamaExtract -Prompt $PatchPrompt -Model $Model -MaxTokens 2048 -Temperature 0.2
if (-not $extract.Success) {
  Write-Error "[patch] Extraction failed: $($extract.Error)"
  exit 3
}
$patchPlan = $extract.ParsedObject

if (-not $patchPlan.patch) {
  Write-Host "[patch] SKIP: $($patchPlan.reason)"
  exit 0
}

# ── 3. Locate section ──
$findText = $patchPlan.find_text
Write-Host "[patch] Locating: $($patchPlan.section_name)"

$exactIdx = $originalContent.IndexOf($findText)
if ($exactIdx -ge 0) {
  Write-Host "  Exact match at pos $exactIdx"
  $updatedContent = $originalContent.Replace($findText, $patchPlan.replace_text)
} else {
  # Fuzzy: try normalized whitespace
  $normalizedFind = $findText -replace '\s+', ' '
  $normalizedContent = $originalContent -replace '\s+', ' '
  $fuzzyIdx = $normalizedContent.IndexOf($normalizedFind)
  if ($fuzzyIdx -ge 0) {
    Write-Host "  Fuzzy match at norm pos $fuzzyIdx"
    $updatedContent = $originalContent -replace [regex]::Escape($findText), $patchPlan.replace_text
  } else {
    # Try section header
    $lines = $findText -split '\r?\n'
    $headerLine = ($lines | Where-Object { $_ -match '^##|^###|^- ' } | Select-Object -First 1)
    if ($headerLine -and ($originalContent -match "(?m)^\s*$([regex]::Escape($headerLine.Trim()))")) {
      Write-Host "  Found via header: $headerLine"
      $updatedContent = $originalContent -replace [regex]::Escape($findText), $patchPlan.replace_text
    } else {
      Write-Error "[patch] Cannot locate section. Use more specific description."
      exit 2
    }
  }
}

# ── 4. Validate ──
Write-Host "[patch] Validating..."
$requiredSections = @('When to use', 'Steps', 'Verification')
$missing = @($requiredSections | Where-Object { $updatedContent -notmatch "(?i)$_" })
if ($missing.Count -gt 0 -and -not $Force) {
  Write-Error "[patch] VALIDATION FAILED: missing $($missing -join ', ')"
  Write-Host "[patch] Skill NOT modified."
  exit 4
}

# ── 5. Dry run ──
if ($DryRun) {
  Write-Host "`n=== DRY RUN ==="
  Write-Host "Section: $($patchPlan.section_name)"
  Write-Host "Reason: $($patchPlan.reason)"
  Write-Host "`n--- Find (200 chars) ---"
  Write-Host $findText.Substring(0, [Math]::Min(200, $findText.Length))
  Write-Host "`n--- Replace (200 chars) ---"
  Write-Host $patchPlan.replace_text.Substring(0, [Math]::Min(200, $patchPlan.replace_text.Length))
  exit 0
}

# ── 6. Atomic write with backup ──
Write-Host "[patch] Applying via atomic write..."
$writeResult = Write-AtomicFile -TargetPath $skillFile -Content $updatedContent -Source "patch:$SkillName"
if (-not $writeResult.Written) {
  Write-Error "[patch] Write failed: $($writeResult.Error)"
  Write-Host "[patch] Backup at: $($writeResult.BackupPath)"
  exit 5
}

# Bump version
$finalContent = [System.IO.File]::ReadAllText($skillFile)
$newVersion = '0.1.1'
if ($finalContent -match 'version:\s*([\d.]+)') {
  $v = [version]$matches[1]
  $newVersion = "$($v.Major).$($v.Minor).$($v.Build + 1)"
}
$finalContent = $finalContent -replace 'version:\s*[\d.]+', "version: $newVersion"
$finalContent = $finalContent -replace 'auto_generated:\s*true', "auto_generated: true`npatched_date: $(Get-Date -Format 'yyyy-MM-dd')"
Write-AtomicFile -TargetPath $skillFile -Content $finalContent -Source "patch-ver:$SkillName" -SkipSecurity | Out-Null

Write-Host "[patch] PATCHED: $SkillName v$newVersion"
Write-Host "  Section: $($patchPlan.section_name) | Reason: $($patchPlan.reason)"
Write-Host "  Backup: $($writeResult.BackupPath)"
if ($Json) { @{patched=$true; skill=$SkillName; version=$newVersion} | ConvertTo-Json -Compress }
