# PreToolUse guard — block L3+ in unattended mode, warn on risky patterns
# Enhanced: warn tier, GitHub PAT detection, context-aware heuristics
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }

try {
  $data = $raw | ConvertFrom-Json
  $toolName = ($data.tool_name ?? $data.toolName ?? "")
  $toolInput = $data.tool_input ?? $data.toolInput ?? @{}
  $inputStr = ($toolInput | ConvertTo-Json -Depth 3 -Compress) + " $toolName"

  # Hard blocklist — credential leaks and system drive writes only
  $bad = @("token=","password=",
           "ghp_[A-Za-z0-9]{36}","sk-[A-Za-z0-9]{32,}",
           "C:\\")

  # Soft warning tier — allow but log
  $warn = @("\.env\b","browser-profile","CREDENTIALS\.md")

  $blocked = $false
  $warned = $false
  $reason = ""
  $warnReason = ""

  # Check hard blocklist
  foreach ($p in $bad) {
    if ($inputStr -match $p) {
      $blocked = $true
      $reason = "L3+/L4 blocked: matched '$p'. Needs human confirmation or risk_ack=true from human."
      break
    }
  }

  # Check soft warning tier (only if not already blocked)
  if (-not $blocked) {
    foreach ($p in $warn) {
      if ($inputStr -match $p) {
        $warned = $true
        $warnReason = "Warning: matched '$p'. Proceeding but logged for audit."
        break
      }
    }
  }

  # Mistake-log check for Edit/Write operations (only if not already blocked)
  if (-not $blocked -and $toolName -in @("Edit","Write")) {
    $mistakeLog = Join-Path $env:USERPROFILE ".claude\projects\D--Code\memory\mistake-log.md"
    if (Test-Path $mistakeLog) {
      try {
        $mistakes = Get-Content $mistakeLog -Raw -Encoding UTF8
        $keywords = ($toolInput | ConvertTo-Json -Depth 3 -Compress) -replace '[^a-zA-Z0-9一-鿿_-]',' '
        $kwList = ($keywords -split '\s+' | Where-Object { $_.Length -gt 3 } | Select-Object -Unique)
        $noiseWords = @("Code","test","Edit","file_path","tool_name","tool_input","old_string","new_string","Write","Read","Glob","Grep")
        $foundKws = @()
        foreach ($kw in $kwList) {
          if ($kw -notin $noiseWords -and $mistakes -match $kw) {
            $foundKws += $kw
          }
        }
        if ($foundKws.Count -gt 0) {
          $warned = $true
          $warnReason = "Mistake-log matched keywords: $($foundKws -join ', '). Check mistake-log before proceeding."
        }
      } catch {
        # Non-fatal: can't read mistake log
      }
    }
  }

  # Agent Hub external send check — block agent-ask.ps1 with sensitive paths
  if (-not $blocked -and $inputStr -match 'agent-ask(?!\w)|/v1/agent/run') {
    $sensitivePaths = @(
      '\.env\b','\.pem\b','\.key\b','\.ssh[\\/]','\.git[\\/]credentials',
      'settings\.local\.json','\.npmrc\b','\.pypirc\b','credentials\.json',
      'secrets\.json','token\.json','browser-profile'
    )
    foreach ($sp in $sensitivePaths) {
      if ($inputStr -match $sp) {
        $blocked = $true
        $reason = "L4 BLOCKED: agent-ask.ps1 sending sensitive path (matched '$sp'). External model must not receive credentials. Remove sensitive paths or use a local agent."
        break
      }
    }
    # Also check for credential patterns in the prompt content
    if (-not $blocked -and $inputStr -match '(?:password|token|secret|api[_-]?key)\s*[=:]\s*\S+') {
      $blocked = $true
      $reason = "L4 BLOCKED: agent-ask.ps1 with credential-like content detected. Redact before sending to external model."
    }
  }

  # Build output
  if ($blocked) {
    $d = @{ hookSpecificOutput = @{
      hookEventName = "PreToolUse"
      permissionDecision = "deny"
      permissionDecisionReason = $reason
    }}
    New-Item -ItemType Directory -Force -Path "D:\Code\ai-infra\tasks\blocked" | Out-Null
    @{ts=(Get-Date -Format "o");tool=$toolName;reason=$reason;level="blocked"} | ConvertTo-Json |
      Out-File "D:\Code\ai-infra\tasks\blocked\blocked-$(Get-Date -Format 'yyyyMMdd-HHmmss').json" -Encoding UTF8
  } elseif ($warned) {
    $d = @{ hookSpecificOutput = @{
      hookEventName = "PreToolUse"
      permissionDecision = "allow"
      permissionDecisionReason = $warnReason
    }}
    # Log warning
    New-Item -ItemType Directory -Force -Path "D:\Code\ai-infra\tasks\blocked" | Out-Null
    @{ts=(Get-Date -Format "o");tool=$toolName;reason=$warnReason;level="warning"} | ConvertTo-Json |
      Out-File "D:\Code\ai-infra\tasks\blocked\warn-$(Get-Date -Format 'yyyyMMdd-HHmmss').json" -Encoding UTF8
  } else {
    $d = @{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = "allow" }}
  }

  $d | ConvertTo-Json -Depth 5
  exit 0
} catch {
  exit 0
}
