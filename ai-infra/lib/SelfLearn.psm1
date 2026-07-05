# SelfLearn.psm1 — 自学习基础设施模块
# 三层架构: Core(模型) → Security(安全) → FileOps(写入)
# 所有自学习脚本共享，一处修bug全局生效
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:ModuleRoot = Split-Path -Parent $PSCommandPath
$Script:ProjectRoot = Split-Path -Parent $Script:ModuleRoot

# ═══════════════════════════════════════════
# LAYER 1: CORE — LLM Adapter
# ═══════════════════════════════════════════

function Invoke-OllamaExtract {
    <#
    .SYNOPSIS
    调用 Ollama 并返回结构化结果。统一处理：调用、JSON提取、转义修复、状态报告。
    所有自学习脚本共享此函数，修一处全局生效。
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,
        [string]$Model = "qwen2.5-coder:latest",
        [int]$MaxTokens = 4096,
        [float]$Temperature = 0.3,
        [int]$TimeoutSec = 120,
        [string]$OllamaUrl = "http://127.0.0.1:11434/api/generate"
    )

    $result = [PSCustomObject]@{
        Success = $false
        RawText = ''
        ParsedObject = $null
        JsonText = ''
        Repairs = @()
        Error = ''
        TokenCount = 0
    }

    # Step 1: Call Ollama
    try {
        $body = @{
            model = $Model
            prompt = $Prompt
            stream = $false
            options = @{ temperature = $Temperature; num_predict = $MaxTokens }
        } | ConvertTo-Json -Compress -Depth 4

        $response = Invoke-RestMethod -Uri $OllamaUrl -Method Post -Body $body -ContentType 'application/json' -TimeoutSec $TimeoutSec
        $result.RawText = $response.response.Trim()
        $result.TokenCount = if ($response.eval_count) { $response.eval_count } else { 0 }
    } catch {
        $result.Error = "Ollama call failed: $_"
        return $result
    }

    # Step 2: Extract JSON from markdown wrapper / thinking prefix
    $jsonText = $result.RawText
    $m = [regex]::Match($jsonText, '(?s)```(?:json)?\s*\r?\n(.*?)\r?\n```')
    if ($m.Success) {
        $jsonText = $m.Groups[1].Value
        $result.Repairs += "stripped markdown wrapper"
    }
    $m2 = [regex]::Match($jsonText, '(?s)  response\s*(.*)')
    if ($m2.Success) {
        $jsonText = $m2.Groups[1].Value
        $result.Repairs += "stripped thinking prefix"
    }
    $jsonText = $jsonText.Trim()
    if (-not $jsonText.StartsWith('{') -and -not $jsonText.StartsWith('[')) {
        $idx = [Math]::Max($jsonText.IndexOf('{'), $jsonText.IndexOf('['))
        if ($idx -ge 0) {
            $jsonText = $jsonText.Substring($idx)
            $result.Repairs += "extracted from surrounding text"
        }
    }

    # Step 3: Fix common JSON escape issues (conservative — only backslash before non-JSON escapes)
    $jsonText = $jsonText -replace '\\(?!["\\/bfnrtu])', '\\\\'
    $result.JsonText = $jsonText

    # Step 4: Parse JSON
    try {
        $result.ParsedObject = $jsonText | ConvertFrom-Json
        $result.Success = $true
    } catch {
        $result.Error = "JSON parse failed: $($_.Exception.Message)"
        # Still return — caller can inspect RawText and Error
    }

    return $result
}

# ═══════════════════════════════════════════
# LAYER 2: SECURITY — Policy Gate
# ═══════════════════════════════════════════

# Threat rules — single source of truth for all scripts
$Script:ThreatRules = @(
    # P0: Prompt Injection
    @{pattern='(?i)ignore\s+.*?(previous|all|above|prior|following|current|system)\s+instructions'; severity='P0'; category='prompt_injection'; description='Override system instructions'},
    @{pattern='(?i)(do\s+not|don''t)\s+(tell|inform|show|reveal|disclose)\s+(the\s+)?user'; severity='P0'; category='deception_hide'; description='Hide information from user'},
    @{pattern='(?i)(you\s+are|act\s+as|pretend\s+to\s+be)\s+(now\s+)?(an?\s+)?(different|new|evil|malicious|unrestricted|DAN|jailbroken)'; severity='P0'; category='role_override'; description='Change agent identity'},
    # P0: Credential leaks
    @{pattern='(?i)curl\s+[^\n]*\$\{?\w*(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH)'; severity='P0'; category='exfil_curl'; description='Curl exfiltrating credentials'},
    @{pattern='(?i)(send|post|upload|transmit|exfiltrate).*(api[_.-]?key|token|secret|password|credential)'; severity='P0'; category='exfil_api'; description='Exfiltrate via API'},
    @{pattern='(?i)(sk-[a-zA-Z0-9]{20,})'; severity='P0'; category='openai_key_leak'; description='OpenAI/Anthropic API key pattern'},
    @{pattern='(?i)(github_pat_[a-zA-Z0-9_]{20,}|ghp_[a-zA-Z0-9]{20,})'; severity='P0'; category='github_token_leak'; description='GitHub PAT detected'},
    # P1: Suspicious
    @{pattern='(?i)(delete|remove|wipe|erase|destroy)\s+(all|every)\s+(memory|file|skill|backup)'; severity='P1'; category='mass_destruction'; description='Mass-delete attempt'},
    @{pattern='(?i)(never|do\s+not)\s+(save|write|record|store)\s+(this|that|memory)'; severity='P1'; category='memory_suppression'; description='Suppress memory recording'},
    @{pattern='(?i)(bypass|disable|turn\s+off)\s+(security|safety|guard|gate|check|filter|scan)'; severity='P1'; category='security_bypass'; description='Bypass security checks'},
    @{pattern='(?i)(\.env|\.env\.\w+|credentials\.json|secrets\.\w+|\.aws/credentials)'; severity='P1'; category='env_file_ref'; description='Reference to credential files'},
    # P2: Gray area
    @{pattern='(?i)(http://|https://)\w+\.(ru|cn|kp|ir)(/|$)'; severity='P2'; category='suspicious_domain'; description='Risky domain TLDs'},
    @{pattern='(?i)eval\s*\(|exec\s*\(|system\s*\(|shell_exec\s*\(|subprocess\.'; severity='P2'; category='code_exec_risk'; description='Code execution functions'}
)

function Test-SecurityThreat {
    <#
    .SYNOPSIS
    扫描内容安全威胁。返回结果对象：Passed, Findings[], HasP0。
    此函数是唯一的安全规则来源——所有脚本调它，不自己复制规则。
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,
        [string]$Source = "unknown"
    )

    $findings = [System.Collections.Generic.List[PSObject]]::new()
    $hasP0 = $false

    foreach ($rule in $Script:ThreatRules) {
        $matches = [regex]::Matches($Content, $rule.pattern)
        foreach ($m in $matches) {
            $ctxStart = [Math]::Max(0, $m.Index - 20)
            $ctxLen = [Math]::Min($Content.Length - $ctxStart, $m.Length + 40)
            $ctx = $Content.Substring($ctxStart, $ctxLen) -replace '\r?\n', ' '
            if ($ctxStart -gt 0) { $ctx = "…$ctx" }
            if ($ctxStart + $ctxLen -lt $Content.Length) { $ctx = "$ctx…" }

            $findings.Add([PSCustomObject]@{
                Severity = $rule.severity
                Category = $rule.category
                Description = $rule.description
                Match = $m.Value
                Context = $ctx
                Source = $Source
            })

            if ($rule.severity -eq 'P0') { $hasP0 = $true }
        }
    }

    return [PSCustomObject]@{
        Passed = (-not $hasP0)
        HasP0 = $hasP0
        FindingCount = $findings.Count
        P0Count = @($findings | Where-Object { $_.Severity -eq 'P0' }).Count
        P1Count = @($findings | Where-Object { $_.Severity -eq 'P1' }).Count
        P2Count = @($findings | Where-Object { $_.Severity -eq 'P2' }).Count
        Findings = @($findings)
        Source = $Source
    }
}

function Test-WritePolicy {
    <#
    .SYNOPSIS
    检查写入路径是否安全——防止路径穿越、写系统目录、覆盖可执行文件。
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [string]$Source = "unknown"
    )

    try { $resolved = (Resolve-Path $FilePath -ErrorAction Stop).Path } catch { $resolved = $FilePath }
    # Normalize — remove .. segments after resolving
    $resolved = [System.IO.Path]::GetFullPath($resolved)

    $issues = @()

    # Path traversal check (after normalization, .. should be resolved)
    if ($resolved -match '\.\.\\' -or $resolved -match '\.\./') {
        $issues += "PATH_TRAVERSAL: $resolved"
    }

    # System directory check
    $forbiddenDirs = @(
        [System.Environment]::GetFolderPath('System'),
        [System.Environment]::GetFolderPath('Windows'),
        'C:\Windows', 'C:\Windows\System32'
    )
    foreach ($dir in $forbiddenDirs) {
        if ($resolved.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase)) {
            $issues += "SYSTEM_DIR: $resolved"
        }
    }

    # Overwrite executable check
    if ($resolved -match '\.(exe|dll|sys|ps1|psm1|js|py)$') {
        $issues += "EXECUTABLE_TARGET: $resolved"
    }

    return [PSCustomObject]@{
        Allowed = ($issues.Count -eq 0)
        Issues = $issues
        ResolvedPath = $resolved
        Source = $Source
    }
}

# ═══════════════════════════════════════════
# LAYER 3: FILEOPS — Atomic File Transactions
# ═══════════════════════════════════════════

$Script:utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-AtomicFile {
    <#
    .SYNOPSIS
    原子写入流程：临时文件→校验→备份→替换→失败回滚。
    所有 memory/skill/volatile-layer 写入必须走此通道。
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetPath,
        [Parameter(Mandatory=$true)]
        [string]$Content,
        [string]$BackupDir,
        [int]$MaxBackups = 5,
        [switch]$SkipSecurity,
        [string]$Source = "unknown"
    )

    $result = [PSCustomObject]@{
        Written = $false
        Path = $TargetPath
        BackupPath = ''
        TempPath = ''
        SecurityCheck = $null
        Error = ''
    }

    # Security scan (unless explicitly skipped)
    if (-not $SkipSecurity) {
        $secResult = Test-SecurityThreat -Content $Content -Source $Source
        $result.SecurityCheck = $secResult
        if ($secResult.HasP0) {
            $p0Items = (@($secResult.Findings) | Where-Object { $_.Severity -eq 'P0' } | ForEach-Object { $_.Category }) -join ', '
            $result.Error = "BLOCKED by security gate: $p0Items"
            return $result
        }
    }

    # Write policy check
    $policyResult = Test-WritePolicy -FilePath $TargetPath -Source $Source
    if (-not $policyResult.Allowed) {
        $result.Error = "BLOCKED by write policy: $($policyResult.Issues -join '; ')"
        return $result
    }

    # Ensure target directory exists
    $targetDir = Split-Path -Parent $TargetPath
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    # Backup existing file
    if (Test-Path $TargetPath) {
        if (-not $BackupDir) { $BackupDir = Join-Path (Split-Path -Parent $TargetPath) '.backups' }
        if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }

        $backupName = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString() + '_' + (Split-Path -Leaf $TargetPath)
        $backupPath = Join-Path $BackupDir $backupName
        Copy-Item $TargetPath $backupPath -Force
        $result.BackupPath = $backupPath

        # Rotate old backups
        $backups = @(Get-ChildItem $BackupDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($backups.Count -gt $MaxBackups) {
            $backups | Select-Object -Skip $MaxBackups | Remove-Item -Force
        }
    }

    # Write to temp file first
    $tempPath = $TargetPath + '.tmp.' + [Guid]::NewGuid().ToString().Substring(0, 8)
    $result.TempPath = $tempPath
    [System.IO.File]::WriteAllText($tempPath, $Content, $Script:utf8NoBom)

    # Verify temp file
    if (-not (Test-Path $tempPath)) {
        $result.Error = "Temp file not created: $tempPath"
        return $result
    }
    $tempContent = [System.IO.File]::ReadAllText($tempPath)
    if ($tempContent.Length -ne $Content.Length) {
        $result.Error = "Temp file verification failed: length mismatch ($($tempContent.Length) vs $($Content.Length))"
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        return $result
    }

    # Atomic replace
    try {
        [System.IO.File]::Delete($TargetPath)
        [System.IO.File]::Move($tempPath, $TargetPath)
        $result.Written = $true
    } catch {
        $result.Error = "Atomic replace failed: $_"
        if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
        # Rollback
        if ($result.BackupPath -and (Test-Path $result.BackupPath)) {
            Copy-Item $result.BackupPath $TargetPath -Force
            $result.Error += " | ROLLED BACK from backup"
        }
    }

    return $result
}

# ═══════════════════════════════════════════
# EXPORTS
# ═══════════════════════════════════════════

Export-ModuleMember -Function @(
    'Invoke-OllamaExtract',
    'Test-SecurityThreat',
    'Test-WritePolicy',
    'Write-AtomicFile'
)

Export-ModuleMember -Variable 'ThreatRules'
