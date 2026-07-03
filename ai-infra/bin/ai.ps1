# ai.ps1 — 统一能力入口 v1
# DeepSeek 只需要记住这一个命令。所有其他工具通过注册表自动路由。
param(
  [Parameter(Position=0)][ValidateSet('preflight','doctor','find','list','exec','start','finish','status')][string]$Command,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Registry = Join-Path $Root 'registry'

function Get-Resources { Get-Content (Join-Path $Registry 'resources.json') -Raw | ConvertFrom-Json }
function Get-Capabilities { Get-Content (Join-Path $Registry 'capabilities.json') -Raw | ConvertFrom-Json }
function Get-Routes { Get-Content (Join-Path $Registry 'routes.json') -Raw | ConvertFrom-Json }

switch ($Command) {
  'preflight' {
    $task = if ($Arguments) { $Arguments -join ' ' } else { '' }
    if (-not $task) { Write-Host "Usage: ai preflight '<task description>'"; exit 1 }
    Write-Host "=== PREFLIGHT ==="
    # Step 1: find matching capability
    Write-Host "[1/3] Matching capability..."
    $caps = Get-Capabilities; $routes = Get-Routes
    $matched = @()
    foreach ($cap in $caps.capabilities) { foreach ($intent in $cap.intents) { if ($task -match $intent) { $matched += $cap; break } } }
    foreach ($route in $routes.routes) { foreach ($kind in $route.match.taskKinds) { if ($task -match $kind -and $matched -notcontains $route) { $matched += $route; break } } }
    if ($matched.Count -eq 0) { Write-Host "  WARN No direct match. Default: model.gpt55"; $matched += $routes.defaults }
    Write-Host "  Found $($matched.Count) match(es)"
    # Step 2: verify registry integrity
    Write-Host "[2/3] Registry check..."
    $regOk = $true
    foreach ($f in @('resources.json','capabilities.json','routes.json')) { $p = Join-Path $Registry $f; if (-not (Test-Path $p)) { Write-Host "  ERR missing: $f"; $regOk = $false } else { try { Get-Content $p -Raw | ConvertFrom-Json | Out-Null } catch { Write-Host "  ERR invalid JSON: $f"; $regOk = $false } } }
    if ($regOk) { Write-Host "  OK" } else { Write-Host "  Run 'ai doctor' to fix" }
    # Step 3: check critical services
    Write-Host "[3/3] Service check..."
    try { $h = Invoke-RestMethod 'http://127.0.0.1:3000/health' -TimeoutSec 3; Write-Host "  GPT-5.5: $($h.status)" } catch { Write-Host "  WARN GPT-5.5: down" }
    try { Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 | Out-Null; Write-Host "  Ollama: up" } catch { Write-Host "  WARN Ollama: down" }
    # Summary
    Write-Host "`n=== PREFLIGHT RESULT ==="
    $matched | ForEach-Object { $id = if ($_.id) { $_.id } else { $_.name }; $p = $_.primary; Write-Host "  → $id : $p" }
    Write-Host "Registry: $(if($regOk){'PASS'}else{'FAIL'})"
    if ($regOk) {
      $env:AI_PREFLIGHT_TOKEN = [Guid]::NewGuid().ToString()
      $env:AI_PREFLIGHT_TIME = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
      Write-Host "PREFLIGHT_TOKEN valid 30min"
    }
    exit $(if($regOk){0}else{1})
  }

  'doctor' {
    Write-Host "=== AI Doctor ==="
    $errors = 0; $warnings = 0

    # Check registry files exist and are valid JSON
    foreach ($f in @('resources.json','capabilities.json','routes.json')) {
      $p = Join-Path $Registry $f
      if (-not (Test-Path $p)) { Write-Host "ERR  missing: $p"; $errors++; continue }
      try { Get-Content $p -Raw | ConvertFrom-Json | Out-Null; Write-Host "OK   $f" } catch { Write-Host "ERR  invalid JSON: $f - $_"; $errors++ }
    }

    # Check that CLAUDE.md references resolve (search across all relevant dirs)
    $claudeMd = Join-Path $Root '..' 'CLAUDE.md'
    $searchDirs = @($Root, (Join-Path $Root '..' 'ai-pipeline'), (Join-Path $Root '..' '.claude'))
    if (Test-Path $claudeMd) {
      $refs = [regex]::Matches((Get-Content $claudeMd -Raw), '(\.?[\w\-]+\.(ps1|json|js|py|md|bat))')
      foreach ($r in $refs) {
        $name = $r.Value
        $found = $false
        foreach ($dir in $searchDirs) {
          if (Get-ChildItem $dir -Recurse -Name -Filter $name -ErrorAction SilentlyContinue) { $found = $true; break }
        }
        # Also check memory dir
        if (-not $found) {
          $memDir = "C:\Users\ZHUYU\.claude\projects\D--Code\memory"
          if (Test-Path $memDir) {
            if (Get-ChildItem $memDir -Recurse -Name -Filter $name -ErrorAction SilentlyContinue) { $found = $true }
          }
        }
        if (-not $found) { Write-Host "WARN CLAUDE.md refs non-existent: $name"; $warnings++ }
      }
    }

    # Check services
    try { $h = Invoke-RestMethod 'http://127.0.0.1:3000/health' -TimeoutSec 3; Write-Host "OK   GPT-5.5 server: $($h.status)" } catch { Write-Host "WARN GPT-5.5 server not responding"; $warnings++ }
    try { $o = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3; Write-Host "OK   Ollama: $($o.models.Count) models" } catch { Write-Host "WARN Ollama not responding"; $warnings++ }

    # Check duplicates in resources
    $res = Get-Resources
    $seen = @{}; $dupes = [System.Collections.Generic.List[string]]::new()
    foreach ($cat in $res.scripts.PSObject.Properties) {
      foreach ($s in $cat.Value) {
        if ($s.status -eq 'duplicate') { $dupes.Add("$($s.id) duplicates $($s.note)") }
      }
    }
    if ($dupes.Count -gt 0) { Write-Host "WARN $($dupes.Count) duplicate scripts:"; $dupes | ForEach-Object { Write-Host "     $_" }; $warnings += $dupes.Count }

    # --strict: cross-reference checks + forbidden paths
    $strict = $Arguments -contains '--strict'
    if ($strict) {
      Write-Host "`n=== STRICT ==="
      # Verify capability→resource references
      $caps = Get-Capabilities
      $routes = Get-Routes
      $allIds = [System.Collections.Generic.HashSet[string]]::new()
      # Collect all resource IDs recursively (handles nested categories like scripts→desktop→[...])
      function Collect-Ids($obj) {
        if ($obj -is [array]) { foreach ($item in $obj) { if ($item.id) { $allIds.Add($item.id) | Out-Null } } }
        elseif ($obj -is [PSCustomObject] -or $obj -is [hashtable]) {
          foreach ($prop in $obj.PSObject.Properties) { Collect-Ids $prop.Value }
        }
      }
      Collect-Ids $res.resources
      foreach ($cap in $caps.capabilities) {
        if ($cap.primary -and -not $allIds.Contains($cap.primary) -and $cap.primary -notmatch '^builtin\.|^policy\.') { Write-Host "ERR  cap $($cap.id) primary $($cap.primary) not in resources"; $errors++ }
        if ($cap.fallbacks) { foreach ($fb in $cap.fallbacks) { if (-not $allIds.Contains($fb) -and $fb -notmatch '^builtin\.|^policy\.') { Write-Host "ERR  cap $($cap.id) fallback $fb not in resources"; $errors++ } } }
        if ($cap.fallback -and $cap.fallback -notmatch '^builtin\.|^policy\.') { if (-not $allIds.Contains($cap.fallback)) { Write-Host "ERR  cap $($cap.id) fallback $($cap.fallback) not in resources"; $errors++ } }
      }
      foreach ($route in $routes.routes) {
        if ($route.requiredSkills) { foreach ($sid in $route.requiredSkills) { if (-not $allIds.Contains($sid)) { Write-Host "ERR  route $($route.id) skill $sid not in resources"; $errors++ } } }
      }
      # Forbidden paths
      try {
        $forbidden = Get-Content (Join-Path $Registry 'forbidden.json') -Raw | ConvertFrom-Json
        foreach ($fp in ($forbidden.forbidden_paths + $forbidden.forbidden_files)) {
          if (Test-Path (Join-Path $Root '..' $fp)) { Write-Host "ERR  forbidden path exists: $fp"; $errors++ }
        }
      } catch { Write-Host "WARN forbidden.json not found or invalid" }
    }

    Write-Host "`nResult: $errors errors, $warnings warnings"
    if ($errors -gt 0) { exit 2 } elseif ($warnings -gt 0) { exit 1 } else { exit 0 }
  }

  'find' {
    $query = $Arguments -join ' '
    if (-not $query) { Write-Host "Usage: ai find <task description>"; exit 1 }
    Write-Host "Searching for: $query"
    $caps = Get-Capabilities
    $routes = Get-Routes
    $matched = @()
    foreach ($cap in $caps.capabilities) {
      foreach ($intent in $cap.intents) {
        if ($query -match $intent) { $matched += $cap; break }
      }
    }
    foreach ($route in $routes.routes) {
      foreach ($kind in $route.match.taskKinds) {
        if ($query -match $kind -and $matched -notcontains $route) { $matched += $route; break }
      }
    }
    if ($matched.Count -eq 0) { Write-Host "No direct match. Default route: model.gpt55"; $matched += $routes.defaults }
    Write-Host "`nMatched ($($matched.Count)):"
    $matched | ForEach-Object {
      $id = if ($_.id) { $_.id } else { $_.name }
      $primary = $_.primary
      $fallback = if ($_.fallbacks) { $_.fallbacks -join ',' } elseif ($_.fallback) { $_.fallback } else { 'none' }
      Write-Host "  $id → primary=$primary fallback=$fallback"
    }
  }

  'list' {
    $filter = if ($Arguments) { $Arguments -join ' ' } else { '' }
    $caps = Get-Capabilities
    Write-Host "=== Capabilities ($($caps.capabilities.Count)) ==="
    foreach ($cap in $caps.capabilities) {
      if ($filter -and $cap.id -notmatch $filter -and $cap.name -notmatch $filter) { continue }
      Write-Host "  $($cap.id) : $($cap.name) → $($cap.primary)"
    }
  }

  'exec' {
    if (-not $Arguments -or -not $Arguments[0]) { Write-Host "Usage: ai exec <capability-id> [args...]"; Write-Host "Run 'ai list' to see all capabilities"; exit 1 }
    $capId = $Arguments[0]
    $rest = if ($Arguments.Count -gt 1) { $Arguments[1..($Arguments.Count - 1)] } else { @() }

    # Resolve capability from registry
    $caps = Get-Capabilities
    $cap = $caps.capabilities | Where-Object { $_.id -eq $capId } | Select-Object -First 1
    if (-not $cap) { Write-Host "ERR  capability not found: $capId"; Write-Host "Run 'ai list' to see all capabilities"; exit 1 }

    $env:AI_ORCHESTRATED = '1'

    # Route based on primary resource type
    $primary = $cap.primary
    switch -Wildcard ($primary) {
      'model.gpt55'       { $prompt = $rest -join ' '; & (Join-Path $Root 'scripts' 'gpt-ask.ps1') -Prompt $prompt -TimeoutSec 300; exit $LASTEXITCODE }
      'model.glm52'       { $prompt = $rest -join ' '; & (Join-Path $Root 'scripts' 'glm-ask.ps1') -Prompt $prompt; exit $LASTEXITCODE }
      'model.ollama-qwen' { Write-Host "Use Ollama directly: http://127.0.0.1:11434"; exit 0 }
      'model.doubao*'     { $envFile = Join-Path $Root '..' 'ai-pipeline' '.env.ps1'; if(Test-Path $envFile){ . $envFile 2>$null }; $imgPath = if($rest.Count -gt 0){ $rest[0] } else { '' }; $prompt = if($rest.Count -gt 1){ $rest[1..($rest.Count-1)] -join ' ' } else { '描述这张截图' }; if($imgPath -and (Test-Path $imgPath)){ $result = & node (Join-Path $Root '..' 'ai-pipeline' 'vision.js') $imgPath $prompt 2>&1; Write-Output $result; exit $LASTEXITCODE } else { Write-Host "Usage: ai exec cap.vision-screenshot <image-path> [prompt]"; exit 1 } }
      'script.health*'    { & (Join-Path $Root 'scripts' 'health-check.ps1') @rest; exit $LASTEXITCODE }
      'script.ai-doctor'  { & $PSCommandPath doctor @rest; exit $LASTEXITCODE }
      'script.memory-*'   { & (Join-Path $Root 'scripts' "memory-$($primary.Split('.')[1].Split('-')[0]).ps1") @rest; exit $LASTEXITCODE }
      'script.*'          { $scriptName = ($primary -replace '^script\.','') + '.ps1'; $scriptPath = Join-Path $Root 'scripts' $scriptName; if (Test-Path $scriptPath) { & $scriptPath @rest; exit $LASTEXITCODE } else { Write-Host "ERR  script not found: $scriptName"; exit 1 } }
      'agent.*'           { Write-Host "Use Agent tool: Agent { subagent_type: '$($primary -replace '^agent\.','')' }"; exit 0 }
      'mcp.*'             { Write-Host "Use MCP tools directly. Category: $primary"; exit 0 }
      'skill.*'           { Write-Host "Use Skill tool: Skill { skill: '$($primary -replace '^skill\.','')' }"; exit 0 }
      'policy.*'          { Write-Host "Policy check: $($cap.name). If destructive, confirm with boss first."; exit 0 }
      default             { Write-Host "ERR  unknown primary resource type: $primary"; exit 1 }
    }
  }

  'status' {
    Write-Host "=== AI Runtime Status ==="
    Write-Host "Registry: $Registry"
    foreach ($f in @('resources.json','capabilities.json','routes.json')) {
      $p = Join-Path $Registry $f; $s = if (Test-Path $p) { "OK" } else { "MISSING" }; Write-Host "  $f : $s"
    }
    try { $h = Invoke-RestMethod 'http://127.0.0.1:3000/health' -TimeoutSec 3; Write-Host "GPT-5.5: busy=$($h.busy) $($h.status)" } catch { Write-Host "GPT-5.5: DOWN" }
    try { $o = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3; Write-Host "Ollama: $($o.models.Count) models" } catch { Write-Host "Ollama: DOWN" }
  }

  default {
    Write-Host @"
ai.ps1 — AI Runtime Entrypoint v1
Commands:
  ai doctor          Check registry health, dead refs, services, duplicates
  ai find <task>     Find matching capability/route for a task description
  ai list [filter]   List all registered capabilities
  ai status          Show runtime status
  ai start <task>    Start a new task (NYI)
  ai finish          Close current task (NYI)
  ai exec <cap>      Execute via capability (NYI)
"@
  }
}
