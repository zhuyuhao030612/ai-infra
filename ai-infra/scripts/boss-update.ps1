# boss-update.ps1 — blocker status report
param([string]$Status="",[string]$Done="",[string]$Blocked="",[string]$Tried="",[string]$Next="",[string]$NeedFromBoss="",[string]$RootDir=$(if($env:CLAUDE_PROJECT_DIR){$env:CLAUDE_PROJECT_DIR}else{"D:\Code"}))
Set-StrictMode -Version 2.0;$ErrorActionPreference="Continue"
$RootDir=[IO.Path]::GetFullPath($RootDir);$stateDir=Join-Path $RootDir ".ai-state";New-Item -ItemType Directory -Force -Path $stateDir|Out-Null
$file=Join-Path $stateDir "boss-update.md"
@"
# 状态汇报 — $(Get-Date -Format "yyyy-MM-dd HH:mm")
**状态**: $Status | **已完成**: $Done | **卡点**: $Blocked | **已尝试**: $Tried | **下一步**: $Next | **需要老板**: $(if($NeedFromBoss){$NeedFromBoss}else{'无需'})
"@|Out-File -LiteralPath $file -Encoding UTF8
Write-Host "Boss update: $file";Get-Content $file
