# ai.ps1 — 统一能力入口 v1
# DeepSeek 只需要记住这一个命令。所有其他工具通过注册表自动路由。
param(
  [ValidateSet('preflight','doctor','find','list','exec','start','finish','status','nudge','crystallize','security-gate','patch','search','profile')][string]$Command,
  [switch]$Json
)
$ErrorActionPreference = 'Stop'
$Arguments = @($args)
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

    # Step 1: match capability + route (inline, not recursive)
    Write-Host "[1/4] Matching capability..."
    $caps = Get-Capabilities; $routes = Get-Routes
    $routeMatch = $null; $capMatch = $null
    foreach ($route in $routes.routes) {
      foreach ($kind in $route.match.taskKinds) { if ($task -match $kind) { $routeMatch = $route; break } }
      if ($routeMatch) { break }
    }
    foreach ($cap in $caps.capabilities) {
      foreach ($intent in $cap.intents) { if ($task -match $intent) { $capMatch = $cap; break } }
      if ($capMatch) { break }
    }
    if ($routeMatch) { Write-Host "  Route: $($routeMatch.id) -> $($routeMatch.primary)" }
    if ($capMatch) { Write-Host "  Cap: $($capMatch.id) -> $($capMatch.primary)" }
    if (-not $routeMatch -and -not $capMatch) {
      Write-Host "  NO MATCH. Refusing preflight."
      Write-Host "  Hint: check capabilities.json / routes.json or run 'ai list'"
      exit 2
    }
    Write-Host "  Found $((@($routeMatch,$capMatch) | Where-Object {$_}).Count) match(es)"

    # Step 2: verify registry integrity
    Write-Host "[2/4] Registry check..."
    $regOk = $true
    foreach ($f in @('resources.json','capabilities.json','routes.json')) {
      $p = Join-Path $Registry $f
      if (-not (Test-Path $p)) { Write-Host "  ERR missing: $f"; $regOk = $false }
      else { try { Get-Content $p -Raw | ConvertFrom-Json | Out-Null } catch { Write-Host "  ERR invalid JSON: $f"; $regOk = $false } }
    }
    if ($regOk) { Write-Host "  OK" } else { Write-Host "  Run 'ai doctor' to fix" }

    # Step 3: check critical services
    Write-Host "[3/4] Service check..."
    try { $h = Invoke-RestMethod 'http://127.0.0.1:3000/health' -TimeoutSec 3; Write-Host "  GPT-5.5: $(if($h.alive){'up'}else{'unknown'})" } catch { Write-Host "  WARN GPT-5.5: down" }
    try { Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 | Out-Null; Write-Host "  Ollama: up" } catch { Write-Host "  WARN Ollama: down" }

    # Step 4: refresh volatile cache layer (prompt caching optimization)
    Write-Host "[4/4] Refreshing volatile layer..."
    $volScript = Join-Path (Join-Path $Root 'scripts') 'gen-volatile-layer.ps1'
    try { & $volScript 2>&1 | Out-Null; Write-Host "  CLAUDE.md volatile layer: refreshed" } catch { Write-Host "  WARN volatile layer: refresh failed" }

    # Summary
    Write-Host "`n=== PREFLIGHT RESULT ==="
    if ($routeMatch) { Write-Host "  Route: $($routeMatch.id) -> $($routeMatch.primary)" }
    if ($capMatch) { Write-Host "  Cap: $($capMatch.id) -> $($capMatch.primary)" }
    Write-Host "Registry: $(if($regOk){'PASS'}else{'FAIL'})"
    if ($regOk) {
      # Write preflight state to file (cross-process safe)
      $stateDir = Join-Path $Root 'runtime'
      New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
      $stateFile = Join-Path $stateDir 'preflight-state.json'
      @{
        token = [Guid]::NewGuid().ToString()
        timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
        task = $task
      } | ConvertTo-Json -Compress | Set-Content -LiteralPath $stateFile -Encoding UTF8
      Write-Host "PREFLIGHT_TOKEN valid 30min (file-based, cross-process)"
    }
    exit $(if($regOk){0}else{1})
  }

  'doctor' {
    Write-Host "=== AI Doctor ==="
    $errors = 0; $warnings = 0

    foreach ($f in @('resources.json','capabilities.json','routes.json')) {
      $p = Join-Path $Registry $f
      if (-not (Test-Path $p)) { Write-Host "ERR  missing: $p"; $errors++; continue }
      try { Get-Content $p -Raw | ConvertFrom-Json | Out-Null; Write-Host "OK   $f" } catch { Write-Host "ERR  invalid JSON: $f - $_"; $errors++ }
    }

    $claudeMd = Join-Path (Join-Path $Root '..') 'CLAUDE.md'
    $searchDirs = @($Root, (Join-Path $Root '..'), (Join-Path (Join-Path $Root '..') 'ai-pipeline'), (Join-Path (Join-Path $Root '..') '.claude'))
    if (Test-Path $claudeMd) {
      $refs = [regex]::Matches((Get-Content $claudeMd -Raw), '(\.?[\w\-]+\.(ps1|json|js|py|md|bat))')
      foreach ($r in $refs) {
        $name = $r.Value
        $found = $false
        foreach ($dir in $searchDirs) {
          if (Get-ChildItem $dir -Recurse -Name -Filter $name -ErrorAction SilentlyContinue) { $found = $true; break }
        }
        if (-not $found) {
          $memDir = "C:\Users\ZHUYU\.claude\projects\D--Code\memory"
          if (Test-Path $memDir) {
            if (Get-ChildItem $memDir -Recurse -Name -Filter $name -ErrorAction SilentlyContinue) { $found = $true }
          }
        }
        if (-not $found) { Write-Host "WARN CLAUDE.md refs non-existent: $name"; $warnings++ }
      }
    }

    try { $h = Invoke-RestMethod 'http://127.0.0.1:3000/health' -TimeoutSec 3; Write-Host "OK   GPT-5.5 server: $(if($h.alive){'up'}else{'unknown'})" } catch { Write-Host "WARN GPT-5.5 server not responding"; $warnings++ }
    try { $o = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3; Write-Host "OK   Ollama: $($o.models.Count) models" } catch { Write-Host "WARN Ollama not responding"; $warnings++ }

    $res = Get-Resources
    $dupes = [System.Collections.Generic.List[string]]::new()
    foreach ($cat in $res.scripts.PSObject.Properties) {
      foreach ($s in $cat.Value) {
        if ($s.status -eq 'duplicate') { $dupes.Add("$($s.id) duplicates $($s.note)") }
      }
    }
    if ($dupes.Count -gt 0) { Write-Host "WARN $($dupes.Count) duplicate scripts:"; $dupes | ForEach-Object { Write-Host "     $_" }; $warnings += $dupes.Count }

    $strict = $Arguments -contains '--strict'
    if ($strict) {
      Write-Host "`n=== STRICT ==="
      $caps = Get-Capabilities
      $routes = Get-Routes
      $allIds = [System.Collections.Generic.HashSet[string]]::new()
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
      try {
        $forbidden = Get-Content (Join-Path $Registry 'forbidden.json') -Raw | ConvertFrom-Json
        foreach ($fp in ($forbidden.forbidden_paths + $forbidden.forbidden_files)) {
          if (Test-Path (Join-Path (Join-Path $Root '..') $fp)) { Write-Host "ERR  forbidden path exists: $fp"; $errors++ }
        }
      } catch { Write-Host "WARN forbidden.json not found or invalid" }
    }

    Write-Host "`nResult: $errors errors, $warnings warnings"
    if ($errors -gt 0) { exit 2 } elseif ($warnings -gt 0) { exit 1 } else { exit 0 }
  }

  'find' {
    $useJson = $Json -or ($Arguments -contains '--json') -or ($Arguments -contains '-Json')
    $queryArgs = @($Arguments | Where-Object { $_ -ne '--json' -and $_ -ne '-Json' })
    $query = $queryArgs -join ' '
    if (-not $query) { Write-Host "Usage: ai find '<task description>' [-Json]"; exit 1 }

    $caps = Get-Capabilities; $routes = Get-Routes
    $routeMatch = $null; $capMatch = $null

    foreach ($route in $routes.routes) {
      foreach ($kind in $route.match.taskKinds) { if ($query -match $kind) { $routeMatch = $route; break } }
      if ($routeMatch) { break }
    }
    foreach ($cap in $caps.capabilities) {
      foreach ($intent in $cap.intents) { if ($query -match $intent) { $capMatch = $cap; break } }
      if ($capMatch) { break }
    }

    if ($useJson) {
      $primary = if ($routeMatch) { $routeMatch.primary } elseif ($capMatch) { $capMatch.primary } else { $null }
      $primaryName = if ($capMatch) { $capMatch.name } elseif ($routeMatch) { $routeMatch.id } else { $null }
      $fallback = if ($routeMatch -and $routeMatch.fallback) { $routeMatch.fallback } elseif ($capMatch -and $capMatch.fallbacks) { ($capMatch.fallbacks | Select-Object -First 1) } else { $null }
      $confidence = if ($routeMatch -and $capMatch) { 'high' } elseif ($routeMatch -or $capMatch) { 'medium' } else { 'none' }
      $result = [ordered]@{
        matched = ($routeMatch -ne $null -or $capMatch -ne $null)
        primary = $primary
        primaryName = $primaryName
        fallback = $fallback
        route = if ($routeMatch) { $routeMatch.id } else { $null }
        requiredSteps = if ($routeMatch -and $routeMatch.requiredSteps) { $routeMatch.requiredSteps } else { @() }
        requiredSkills = if ($capMatch -and $capMatch.requiredSkills) { $capMatch.requiredSkills } else { @() }
        confidence = $confidence
      }
      $result | ConvertTo-Json -Depth 8 -Compress
      if (-not $result.matched) { exit 2 } else { exit 0 }
    }

    if (-not $routeMatch -and -not $capMatch) {
      Write-Host "No matching route or capability."
      Write-Host "Run 'ai list' to see available capabilities."
      exit 2
    }
    Write-Host "Searching for: $query"
    Write-Host "`nMatched:"
    if ($routeMatch) { Write-Host "  $($routeMatch.id) -> $($routeMatch.primary) (route)" }
    if ($capMatch) { Write-Host "  $($capMatch.id) -> $($capMatch.primary) (capability)" }
    if ($routeMatch -and $routeMatch.requiredSteps) { Write-Host "  Steps: $($routeMatch.requiredSteps -join ' -> ')" }
  }

  'list' {
    $filter = if ($Arguments) { $Arguments -join ' ' } else { '' }
    $caps = Get-Capabilities
    Write-Host "=== Capabilities ($($caps.capabilities.Count)) ==="
    foreach ($cap in $caps.capabilities) {
      if ($filter -and $cap.id -notmatch $filter -and $cap.name -notmatch $filter) { continue }
      Write-Host "  $($cap.id) : $($cap.name) -> $($cap.primary)"
    }
  }

  'exec' {
    if (-not $Arguments -or -not $Arguments[0]) { Write-Host "Usage: ai exec <capability-id> [args...]"; Write-Host "Run 'ai list' to see all capabilities"; exit 1 }
    $capId = $Arguments[0]
    $rest = if ($Arguments.Count -gt 1) { $Arguments[1..($Arguments.Count - 1)] } else { @() }

    # Support --file <path> for long prompts (>8191 chars or special characters)
    $fileIdx = [Array]::IndexOf($Arguments, '--file')
    if ($fileIdx -ge 0 -and $fileIdx + 1 -lt $Arguments.Count) {
      $promptFile = $Arguments[$fileIdx + 1]
      if (-not (Test-Path $promptFile)) { Write-Host "ERR  file not found: $promptFile"; exit 1 }
      $fileContent = Get-Content $promptFile -Raw -Encoding UTF8
      $rest = @($fileContent)
      # Remove --file and its value from $rest for downstream consumers
      $restArgs = [System.Collections.ArrayList]::new()
      for ($i = 1; $i -lt $Arguments.Count; $i++) {
        if ($i -eq $fileIdx -or $i -eq $fileIdx + 1) { continue }
        [void]$restArgs.Add($Arguments[$i])
      }
      $rest = if ($restArgs.Count -gt 0) { $restArgs.ToArray() } else { @($fileContent) }
    }

    $caps = Get-Capabilities
    $cap = $caps.capabilities | Where-Object { $_.id -eq $capId } | Select-Object -First 1
    if (-not $cap) { Write-Host "ERR  capability not found: $capId"; Write-Host "Run 'ai list' to see all capabilities"; exit 1 }

    $env:AI_ORCHESTRATED = '1'
    $primary = $cap.primary
    switch -Wildcard ($primary) {
      'model.gpt55'       { $prompt = $rest -join ' '; & (Join-Path (Join-Path $Root 'scripts') 'gpt-ask.ps1') -Prompt $prompt -TimeoutSec 300; exit $LASTEXITCODE }
      'model.glm52'       { $prompt = $rest -join ' '; & (Join-Path (Join-Path $Root 'scripts') 'glm-ask.ps1') -Prompt $prompt; exit $LASTEXITCODE }
      'model.ollama-qwen' { $op = $rest -join ' '; $body = @{model='qwen2.5-coder:latest';prompt=$op;stream=$false} | ConvertTo-Json -Compress; $r = Invoke-RestMethod 'http://127.0.0.1:11434/api/generate' -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 120; Write-Output $r.response; exit 0 }
      'model.doubao*'     { $envFile = Join-Path (Join-Path (Join-Path $Root '..') 'ai-pipeline') '.env.ps1'; if(Test-Path $envFile){ . $envFile 2>$null }; $imgPath = if($rest.Count -gt 0){ $rest[0] } else { '' }; $prompt = if($rest.Count -gt 1){ $rest[1..($rest.Count-1)] -join ' ' } else { '描述这张截图' }; if($imgPath -and (Test-Path $imgPath)){ $result = & node (Join-Path (Join-Path (Join-Path $Root '..') 'ai-pipeline') 'vision.js') $imgPath $prompt 2>&1; Write-Output $result; exit $LASTEXITCODE } else { Write-Host "Usage: ai exec cap.vision-screenshot <image-path> [prompt]"; exit 1 } }

      'script.ai-doctor'  { & $PSCommandPath doctor @rest; exit $LASTEXITCODE }
      'script.memory-*'   { $fullName = $primary -replace '^script\.',''; $scriptPath = Join-Path (Join-Path $Root 'scripts') "$fullName.ps1"; if (Test-Path $scriptPath) { & $scriptPath -Query ($rest -join ' ') ; exit $LASTEXITCODE } else { Write-Host "ERR  script not found: $fullName.ps1"; exit 1 } }
      'script.*'          { $scriptName = ($primary -replace '^script\\.','') + '.ps1'; $scriptPath = Join-Path (Join-Path $Root 'scripts') $scriptName; if (Test-Path $scriptPath) { & $scriptPath @rest; exit $LASTEXITCODE } else { Write-Host "ERR  script not found: $scriptName"; exit 1 } }
      'agent.*'           { $task = $rest -join ' '; $agentName = $primary -replace '^agent\.',''; [ordered]@{type='agent';name=$agentName;task=$task;requiredSteps=if($cap.requiredSteps){$cap.requiredSteps}else{@()};fallbacks=if($cap.fallbacks){$cap.fallbacks}else{@()}} | ConvertTo-Json -Depth 4 -Compress; exit 0 }
      'mcp.*'             { $task = $rest -join ' '; [ordered]@{type='mcp';server=($primary -replace '^mcp\.','');task=$task} | ConvertTo-Json -Compress; exit 0 }
      'skill.*'           { $task = $rest -join ' '; [ordered]@{type='skill';name=($primary -replace '^skill\.','');task=$task} | ConvertTo-Json -Compress; exit 0 }
      'policy.*'          { Write-Host "Policy check: $($cap.name). If destructive, confirm with boss first."; exit 0 }
      'builtin.Bash*'       { $cmd = $rest -join ' '; bash -c $cmd 2>&1; exit $LASTEXITCODE }
      'builtin.PowerShell*'  { $cmd = $rest -join ' '; pwsh -NoProfile -Command $cmd 2>&1; exit $LASTEXITCODE }
      'builtin.*'            { $task = $rest -join ' '; [ordered]@{type='builtin';name=($primary -replace '^builtin\.','');task=$task} | ConvertTo-Json -Compress; exit 0 }
      default             { Write-Host "ERR  unknown primary resource type: $primary"; exit 1 }
    }
  }

  'status' {
    Write-Host "=== AI Runtime Status ==="
    Write-Host "Registry: $Registry"
    foreach ($f in @('resources.json','capabilities.json','routes.json')) {
      $p = Join-Path $Registry $f; $s = if (Test-Path $p) { "OK" } else { "MISSING" }; Write-Host "  $f : $s"
    }
    try { $h = Invoke-RestMethod 'http://127.0.0.1:3000/health' -TimeoutSec 3; Write-Host "GPT-5.5: alive=$($h.alive) busy=$($h.busy)" } catch { Write-Host "GPT-5.5: DOWN" }
    try { $o = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3; Write-Host "Ollama: $($o.models.Count) models" } catch { Write-Host "Ollama: DOWN" }
  }

  'nudge' {
    $desc = if ($Arguments) { $Arguments -join ' ' } else { '' }
    if (-not $desc) { Write-Host "Usage: ai nudge '<session description>' [-DryRun]"; Write-Host "Review the current session and extract memories/skills."; exit 1 }
    $dry = $Arguments -contains '-DryRun' -or $Arguments -contains '--dry-run'
    $nudgeScript = Join-Path (Join-Path $Root 'scripts') 'nudge-review.ps1'
    $cleanArgs = @($Arguments | Where-Object { $_ -ne '-DryRun' -and $_ -ne '--dry-run' })
    $cleanDesc = $cleanArgs -join ' '
    if ($dry) {
      & $nudgeScript -SessionDescription $cleanDesc -DryRun
    } else {
      & $nudgeScript -SessionDescription $cleanDesc
    }
    exit $LASTEXITCODE
  }

  'crystallize' {
    $dry = $Arguments -contains '-DryRun' -or $Arguments -contains '--dry-run'
    $force = $Arguments -contains '-Force' -or $Arguments -contains '--force'
    $crystallizeScript = Join-Path (Join-Path $Root 'scripts') 'skill-crystallize.ps1'

    # Extract -ExecutionLogFile or -ExecutionLog value
    $logFile = ''
    $logIdx = [Array]::IndexOf($Arguments, '-ExecutionLogFile')
    if ($logIdx -ge 0 -and $logIdx + 1 -lt $Arguments.Count) { $logFile = $Arguments[$logIdx + 1] }
    if (-not $logFile) {
      $logIdx = [Array]::IndexOf($Arguments, '-ExecutionLog')
      if ($logIdx -ge 0 -and $logIdx + 1 -lt $Arguments.Count) {
        # Write to temp file
        $tempFile = Join-Path (Join-Path $Root 'runtime') 'crystallize-exec-log.tmp.txt'
        $Arguments[$logIdx + 1] | Set-Content -LiteralPath $tempFile -Encoding UTF8
        $logFile = $tempFile
      }
    }

    # Everything else is task description
    $taskParts = @()
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
      if ($Arguments[$i] -in @('-DryRun','--dry-run','-Force','--force')) { continue }
      if ($Arguments[$i] -in @('-ExecutionLog','-ExecutionLogFile')) { $i++; continue }
      $taskParts += $Arguments[$i]
    }
    $taskDesc = $taskParts -join ' '
    if (-not $taskDesc) { Write-Host "Usage: ai crystallize '<task description>' [-ExecutionLogFile <file>] [-DryRun] [-Force]"; Write-Host "Crystallize a complex task into a reusable SKILL.md."; exit 1 }

    if (-not $logFile) {
      Write-Host "Usage: ai crystallize '<task>' -ExecutionLogFile <file> [-DryRun] [-Force]"
      Write-Host "First write execution log to a file, then pass it with -ExecutionLogFile."
      exit 1
    }
    # Note: can't use splatting for switch params reliably in this pwsh version
    if ($dry -and $force) {
      & $crystallizeScript -TaskDescription $taskDesc -ExecutionLogFile $logFile -DryRun -Force
    } elseif ($dry) {
      & $crystallizeScript -TaskDescription $taskDesc -ExecutionLogFile $logFile -DryRun
    } elseif ($force) {
      & $crystallizeScript -TaskDescription $taskDesc -ExecutionLogFile $logFile -Force
    } else {
      & $crystallizeScript -TaskDescription $taskDesc -ExecutionLogFile $logFile
    }
    exit $LASTEXITCODE
  }

  'security-gate' {
    $content = if ($Arguments) { $Arguments -join ' ' } else { '' }
    if (-not $content) { Write-Host "Usage: ai security-gate '<content>' [-Source '<label>']"; Write-Host "Or: ai security-gate -File <path> [-Source '<label>']"; exit 1 }
    $gateScript = Join-Path (Join-Path $Root 'scripts') 'security-gate.ps1'
    $fileIdx = [Array]::IndexOf($Arguments, '-File')
    if ($fileIdx -ge 0 -and $fileIdx + 1 -lt $Arguments.Count) {
      $filePath = $Arguments[$fileIdx + 1]
      if (Test-Path $filePath) {
        $content = Get-Content $filePath -Raw -Encoding UTF8
      }
    }
    $srcIdx = [Array]::IndexOf($Arguments, '-Source')
    $src = if ($srcIdx -ge 0 -and $srcIdx + 1 -lt $Arguments.Count) { $Arguments[$srcIdx + 1] } else { "manual" }
    & $gateScript -Content $content -Source $src -VerboseOutput
    exit $LASTEXITCODE
  }

  'patch' {
    $patchScript = Join-Path (Join-Path $Root 'scripts') 'skill-patch.ps1'
    $dry = $Arguments -contains '-DryRun' -or $Arguments -contains '--dry-run'
    $force = $Arguments -contains '-Force' -or $Arguments -contains '--force'
    # First non-flag arg is skill name, rest is correction description
    $argsList = @($Arguments | Where-Object { $_ -notin @('-DryRun','--dry-run','-Force','--force') })
    if ($argsList.Count -lt 2) { Write-Host "Usage: ai patch <skill-name> '<correction description>' [-DryRun] [-Force]"; exit 1 }
    $skillName = $argsList[0]
    $correction = $argsList[1..($argsList.Count-1)] -join ' '
    if ($dry -and $force) {
      & $patchScript -SkillName $skillName -Correction $correction -DryRun -Force
    } elseif ($dry) {
      & $patchScript -SkillName $skillName -Correction $correction -DryRun
    } elseif ($force) {
      & $patchScript -SkillName $skillName -Correction $correction -Force
    } else {
      & $patchScript -SkillName $skillName -Correction $correction
    }
    exit $LASTEXITCODE
  }

  'search' {
    $query = if ($Arguments) { $Arguments -join ' ' } else { '' }
    if (-not $query) { Write-Host "Usage: ai search '<query>' [-Limit N]"; exit 1 }
    $fts5Script = Join-Path (Join-Path $Root 'scripts') 'memory-fts5.ps1'
    $rebuild = $Arguments -contains '-Rebuild'
    if ($rebuild) { & $fts5Script -Rebuild -Query $query; exit $LASTEXITCODE }
    & $fts5Script -Query $query
    exit $LASTEXITCODE
  }

  'profile' {
    $review = $Arguments -contains '-Review' -or $Arguments -contains '--review'
    $force = $Arguments -contains '-Force' -or $Arguments -contains '--force'
    $profileScript = Join-Path (Join-Path $Root 'scripts') 'profile-builder.ps1'
    if ($review) { & $profileScript -Review; exit $LASTEXITCODE }
    if ($force) { & $profileScript -Force; exit $LASTEXITCODE }
    & $profileScript
    exit $LASTEXITCODE
  }

  default {
    Write-Host @"
ai.ps1 — AI Runtime Entrypoint v1
Commands:
  ai doctor          Check registry health, dead refs, services, duplicates
  ai find <task>     Find matching capability/route for a task description
  ai list [filter]   List all registered capabilities
  ai status          Show runtime status
  ai nudge <desc>    Review session and auto-extract memories/skills (Nudge engine)
  ai crystallize     Crystallize complex task into reusable SKILL.md
  ai security-gate   Scan content for security threats before memory/skill write
  ai patch <skill>   Fuzzy-patch a skill instead of full rewrite (self-repair)
  ai start <task>    Start a new task (NYI)
  ai finish          Close current task (NYI)
  ai exec <cap>      Execute via capability (NYI)
"@
  }
}
