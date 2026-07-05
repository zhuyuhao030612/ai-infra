# migrate-token-to-env.ps1 -- ANTHROPIC_AUTH_TOKEN 迁移到 .env.ps1 (GPT-5.5编写, DeepSeek审计通过)
param([string]$EnvFile="D:\Code\ai-pipeline\.env.ps1", [string]$VariableName="ANTHROPIC_AUTH_TOKEN", [string]$BackupDir="", [string]$LogFile="", [switch]$WhatIf)
Set-StrictMode -Version Latest; $ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($BackupDir)){$BackupDir=Join-Path (Split-Path $EnvFile) "backups"}
if([string]::IsNullOrWhiteSpace($LogFile)){$LogFile=Join-Path (Split-Path $EnvFile) "migrate-token-to-env.log"}
function Write-Log{param([string]$m,[string]$l="INFO")
 $d=Split-Path $LogFile; if(!(Test-Path $d)){New-Item -ItemType Directory $d -Force|Out-Null}
 $line="[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$l,$m
 Add-Content $LogFile $line -Encoding UTF8; Write-Host $line}
try{
 Write-Log "开始迁移 $VariableName"
 $token=[Environment]::GetEnvironmentVariable($VariableName,"User")
 if(!$token){$token=[Environment]::GetEnvironmentVariable($VariableName,"Process")}
 if(!$token){throw "未找到 $VariableName 用户级或进程级环境变量"}
 if([Environment]::GetEnvironmentVariable($VariableName,"Machine")){Write-Log "检测到机器级变量，不自动迁移" "WARN"}
 Write-Log "检测到token (不输出明文)"
 # Backup
 $bak=$null
 if(Test-Path $EnvFile){$bak=Join-Path $BackupDir ("env.ps1.{0}.bak" -f (Get-Date -Format "yyyyMMdd-HHmmss")); New-Item -ItemType Directory $BackupDir -Force|Out-Null; Copy-Item $EnvFile $bak; Write-Log "已备份: $bak"}
 # Write
 if($WhatIf){Write-Log "[WhatIf] 将写入 $EnvFile";exit 0}
 $escaped=$token.Replace("'","''")
 $line='$env:{0} = ''{1}''' -f $VariableName,$escaped
 if(Test-Path $EnvFile){
  $content=Get-Content $EnvFile -Raw -Encoding UTF8
  if($content -match "(?m)^\s*`$env:$([regex]::Escape($VariableName))\s*="){$content=[regex]::Replace($content,"(?m)^\s*`$env:$([regex]::Escape($VariableName))\s*=.*$",$line);Set-Content $EnvFile $content -Encoding UTF8;Write-Log "已更新现有变量"}
  else{Add-Content $EnvFile "" -Encoding UTF8;Add-Content $EnvFile "# Token迁移写入 $(Get-Date)" -Encoding UTF8;Add-Content $EnvFile $line -Encoding UTF8;Write-Log "已追加变量"}
 }else{Set-Content $EnvFile @("# 本地私有环境变量",$line) -Encoding UTF8;Write-Log "已创建文件并写入"}
 # Remove
 [Environment]::SetEnvironmentVariable($VariableName,$null,"User")
 [Environment]::SetEnvironmentVariable($VariableName,$null,"Process")
 $verify=[Environment]::GetEnvironmentVariable($VariableName,"User")
 if($verify){Write-Log "删除环境变量失败" "ERROR";exit 1}
 Write-Log "迁移完成。新会话需执行: . `"$EnvFile`""
 exit 0
}catch{Write-Log "失败: $($_.Exception.Message)" "ERROR";exit 2}
