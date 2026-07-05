# backup-critical-configs.ps1 — 每日增量备份关键配置 (GPT-5.5 编写，DeepSeek 审计通过)
param(
    [string]$BackupRoot = "D:\Backup",
    [string]$ProjectRoot = "D:\Code",
    [string]$UserClaudeRoot = (Join-Path $env:USERPROFILE ".claude"),
    [string]$MemoryProjectKey = "D--Code",
    [int]$RetentionDays = 7,
    [string]$LogFile = ""
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($LogFile)) { $LogFile = Join-Path $BackupRoot "backup.log" }

function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet("INFO","WARN","ERROR")][string]$Level="INFO")
    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-FileHashSafe {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

function Get-PreviousBackupFile {
    param([Parameter(Mandatory)][string]$RelativePath, [Parameter(Mandatory)][datetime]$Today)
    if (-not (Test-Path $BackupRoot)) { return $null }
    $backupDirs = Get-ChildItem -Path $BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^\d{4}-\d{2}-\d{2}$" } |
        ForEach-Object { try { [pscustomobject]@{ Date = [datetime]::ParseExact($_.Name,"yyyy-MM-dd",$null); Path = $_.FullName } } catch { $null } } |
        Where-Object { $_ -ne $null -and $_.Date.Date -lt $Today.Date } |
        Sort-Object Date -Descending
    foreach ($dir in $backupDirs) {
        $candidate = Join-Path $dir.Path $RelativePath
        if (Test-Path $candidate -PathType Leaf) { return [pscustomobject]@{ FilePath = $candidate; Date = $dir.Date } }
    }
    return $null
}

try {
    $today = Get-Date
    $dateName = $today.ToString("yyyy-MM-dd")
    $todayBackupDir = Join-Path $BackupRoot $dateName
    $retentionCutoff = $today.Date.AddDays(-1 * ($RetentionDays - 1))
    if (-not (Test-Path $todayBackupDir)) { New-Item -ItemType Directory -Path $todayBackupDir -Force | Out-Null }
    Write-Log "开始关键配置备份，目标目录：$todayBackupDir"

    $sources = @(
        @{ Source = Join-Path $UserClaudeRoot "settings.json";           Relative = "UserClaude\settings.json" },
        @{ Source = Join-Path $UserClaudeRoot "settings.local.json";    Relative = "UserClaude\settings.local.json" },
        @{ Source = Join-Path $ProjectRoot ".claude\agent-router.json";  Relative = "Project\.claude\agent-router.json" },
        @{ Source = Join-Path $ProjectRoot ".claude\settings.local.json"; Relative = "Project\.claude\settings.local.json" },
        @{ Source = Join-Path $ProjectRoot "CLAUDE.md";                  Relative = "Project\CLAUDE.md" },
        @{ Source = Join-Path $ProjectRoot ".mcp.json";                  Relative = "Project\.mcp.json" }
    )

    # Memory files
    $memoryDir = Join-Path $UserClaudeRoot ("projects\{0}\memory" -f $MemoryProjectKey)
    if (Test-Path $memoryDir) {
        Get-ChildItem -Path $memoryDir -Filter "*.md" -File | ForEach-Object {
            $sources += @{ Source = $_.FullName; Relative = "UserClaude\projects\$MemoryProjectKey\memory\$($_.Name)" }
        }
    }

    $results = foreach ($item in $sources) {
        if (-not (Test-Path $item.Source -PathType Leaf)) { Write-Log "源文件不存在，跳过：$($item.Source)" "WARN"; continue }
        $targetPath = Join-Path $todayBackupDir $item.Relative
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

        $sourceHash = Get-FileHashSafe -Path $item.Source
        $previous = Get-PreviousBackupFile -RelativePath $item.Relative -Today $today
        if ($null -ne $previous) {
            $previousHash = Get-FileHashSafe -Path $previous.FilePath
            if ($sourceHash -eq $previousHash -and $previous.Date.Date -ge $retentionCutoff.Date) {
                Write-Log "较最近备份无变化，跳过：$($item.Relative)"
                continue
            }
        }
        Copy-Item -Path $item.Source -Destination $targetPath -Force
        Write-Log "已备份：$($item.Relative)"
    }

    # 清理旧备份
    if (Test-Path $BackupRoot) {
        Get-ChildItem -Path $BackupRoot -Directory | Where-Object { $_.Name -match "^\d{4}-\d{2}-\d{2}$" } | ForEach-Object {
            try { if (([datetime]::ParseExact($_.Name,"yyyy-MM-dd",$null)).Date -lt $retentionCutoff.Date) { Remove-Item -Path $_.FullName -Recurse -Force; Write-Log "已清理旧备份：$($_.FullName)" } } catch {}
        }
    }
    Write-Log "备份完成"
    exit 0
} catch { Write-Log "备份失败：$($_.Exception.Message)" "ERROR"; exit 1 }
