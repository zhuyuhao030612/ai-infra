# profile-builder.ps1 — 轻量 Honcho 用户画像（Hermes 偷师补完）
# 从 memory + nudge 日志归纳四类画像，生成 user_profile.md + user_profile.json
param([switch]$Force, [switch]$Json, [switch]$Review)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$MemDir = Join-Path (Join-Path $Root '..') 'memory'
$ProfileMd = Join-Path $MemDir 'user_profile.md'
$ProfileJson = Join-Path $MemDir 'user_profile.json'
$ProfileEvents = Join-Path (Join-Path $Root 'runtime') 'profile-events.jsonl'
$OllamaUrl = 'http://127.0.0.1:11434/api/generate'
$utf8 = New-Object System.Text.UTF8Encoding $false

# ── 1. Gather evidence ──
Write-Host "[profile] Gathering evidence..."

$memories = Get-ChildItem $MemDir -Filter '*.md' -Exclude 'user_profile.md' -ErrorAction SilentlyContinue
$evidenceText = ''
foreach ($f in $memories) {
  $content = Get-Content $f.FullName -Raw -Encoding UTF8
  # Extract frontmatter + first 200 chars of content
  if ($content -match 'description:\s*(.*)') {
    $evidenceText += "$($f.BaseName): $($matches[1])`n"
  }
}

# ── 2. Review mode — just show current profile ──
if ($Review) {
  if (Test-Path $ProfileMd) {
    Write-Host (Get-Content $ProfileMd -Raw -Encoding UTF8)
  } else {
    Write-Host "No profile yet. Run without -Review to build one."
  }
  exit 0
}

# ── 3. Build profile via Ollama ──
Write-Host "[profile] Building via Ollama..."

$prompt = @"
You are a user profile analyst (NOT a psychologist). Analyze the evidence below and produce a collaboration profile.

Evidence (from project memory files and nudge extractions):
$evidenceText

Output ONLY valid JSON:
{
  "communication_style": {
    "value": "e.g. prefers direct, Chinese, conclusion-first. For architecture questions, accepts detailed structured analysis. Dislikes generic fluff.",
    "confidence": "high|medium|low",
    "evidence": "key observations"
  },
  "decision_tendency": {
    "value": "e.g. prefers fastest viable path, accepts short-term technical debt, requires explicit risk points and rollback plans.",
    "confidence": "high|medium|low",
    "evidence": "key observations"
  },
  "technical_preferences": {
    "value": "e.g. PowerShell, Ollama, Python, React/TS, local-first, file-based storage, modular scripts, CLI tools.",
    "confidence": "high|medium|low",
    "evidence": "key observations",
    "taboos": "e.g. dislikes over-engineering, dislikes code without acceptance criteria"
  },
  "current_focus": {
    "value": "e.g. PHS live streaming platform, Hermes self-learning system, User Profile implementation",
    "projects": ["project1", "project2"],
    "ttl_days": 14,
    "confidence": "high|medium|low"
  }
}

Rules:
- Use "用户在技术协作中表现出…" NOT "用户是…人格"
- No psychological diagnosis, personality typing, emotional state guesses
- Only project-relevant collaboration traits
- If uncertain, set confidence to "low"
"@

$body = @{model='qwen2.5-coder:latest'; prompt=$prompt; stream=$false; options=@{temperature=0.3; num_predict=2048}} | ConvertTo-Json -Compress -Depth 4
$resp = Invoke-RestMethod -Uri $OllamaUrl -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 120
$raw = $resp.response.Trim()

# Extract JSON
$jsonText = $raw
# Strip markdown wrapper
$m = [regex]::Match($jsonText, '(?s)```(?:json)?\s*\r?\n(.*?)\r?\n```')
if ($m.Success) { $jsonText = $m.Groups[1].Value; Write-Host "  Stripped markdown wrapper" }
# Strip thinking prefix
$m2 = [regex]::Match($jsonText, '(?s)  response\s*(.*)')
if ($m2.Success) { $jsonText = $m2.Groups[1].Value }
$jsonText = $jsonText.Trim()
# Ensure starts with {
if (-not $jsonText.StartsWith('{')) {
  $idx = $jsonText.IndexOf('{')
  if ($idx -ge 0) { $jsonText = $jsonText.Substring($idx) }
}

try { $profile = $jsonText | ConvertFrom-Json } catch {
  Write-Error "Profile parse failed: $_"
  Write-Error "RAW(500): $($raw.Substring(0, [Math]::Min(500, $raw.Length)))"
  Write-Error "PARSED(500): $($jsonText.Substring(0, [Math]::Min(500, $jsonText.Length)))"
  exit 3
}

# ── 4. Write human-readable profile ──
$md = @"
# User Profile

> 最后更新: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | 自动生成，可手动修改
> 非心理画像——只看协作风格和技术偏好

## 沟通风格
$($profile.communication_style.value)

置信度: $($profile.communication_style.confidence)
证据: $($profile.communication_style.evidence)

## 决策倾向
$($profile.decision_tendency.value)

置信度: $($profile.decision_tendency.confidence)
证据: $($profile.decision_tendency.evidence)

## 技术偏好
$($profile.technical_preferences.value)

置信度: $($profile.technical_preferences.confidence)
证据: $($profile.technical_preferences.evidence)

## 当前工作重点
$($profile.current_focus.value)

置信度: $($profile.current_focus.confidence)
TTL: $($profile.current_focus.ttl_days)天
"@

[System.IO.File]::WriteAllText($ProfileMd, $md, $utf8)
Write-Host "[profile] Wrote user_profile.md"

# ── 5. Write machine-readable profile ──
$profileObj = @{
  version = 1
  updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
  communication_style = $profile.communication_style
  decision_tendency = $profile.decision_tendency
  technical_preferences = $profile.technical_preferences
  current_focus = $profile.current_focus
}
$profileObj | ConvertTo-Json -Depth 4 -Compress | Set-Content $ProfileJson -Encoding UTF8
Write-Host "[profile] Wrote user_profile.json"

# ── 6. Log event ──
$event = @{timestamp=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString(); action='profile_built'; confidence=$profile.communication_style.confidence}
$eventJson = $event | ConvertTo-Json -Compress
Add-Content $ProfileEvents $eventJson -Encoding UTF8
Write-Host "[profile] Done. Run with -Review to check."

if ($Json) { $profile | ConvertTo-Json -Compress }
