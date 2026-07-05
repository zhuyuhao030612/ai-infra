# new-failure.ps1 — failure evidence pack
param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$ErrorType,[Parameter(Mandatory=$true)][string]$Summary,[string]$ErrorText="",[hashtable]$Artifacts=@{},[string]$RootDir=$(if($env:CLAUDE_PROJECT_DIR){$env:CLAUDE_PROJECT_DIR}else{"D:\Code"}))
Set-StrictMode -Version 2.0;$ErrorActionPreference="Continue"
function Get-Prop{param($o,$n,$d=$null)if($null-eq$o){return $d};$p=$o.PSObject.Properties[$n];if($null-eq$p){return $d};return $p.Value}
function Redact-Text{param($t)if(-not$t){return $t};$t=$t -replace '([A-Za-z0-9_\-]{40,})','[TOKEN_REDACTED]';$t=$t -replace '(?i)(password|token|secret|key|authorization)\s*[=:]\s*\S+','$1=[REDACTED]';return $t}
$RootDir=[IO.Path]::GetFullPath($RootDir);$FailuresDir=Join-Path $RootDir "ai-infra\failures"
$safeErrorType=$ErrorType -replace '[\/:*?"<>|]','-';$safeErrorType=$safeErrorType -replace '\.\.','-';if([string]::IsNullOrWhiteSpace($safeErrorType)){$safeErrorType="unknown"}
$runId=Get-Date -Format "yyyyMMdd-HHmmss";$runDir=Join-Path $FailuresDir "$runId-$safeErrorType";New-Item -ItemType Directory -Force -Path $runDir|Out-Null
Redact-Text $ErrorText|Out-File (Join-Path $runDir "error.txt") -Encoding UTF8
$manifestArtifacts=[ordered]@{error="error.txt"}
foreach($k in $Artifacts.Keys){$safeName=([string]$k) -replace '[\/:*?"<>|]','-';$v=[string]$Artifacts[$k];$fileName="$safeName.txt";$v|Out-File (Join-Path $runDir $fileName) -Encoding UTF8;$manifestArtifacts[$safeName]=$fileName}
$manifest=[ordered]@{id="$runId-$safeErrorType";ts=(Get-Date).ToUniversalTime().ToString("o");source=$Source;ok=$false;error_type=$ErrorType;summary=Redact-Text $Summary;artifacts=$manifestArtifacts}
$manifest|ConvertTo-Json -Depth 8|Out-File (Join-Path $runDir "manifest.json") -Encoding UTF8
$dataJson=[ordered]@{error_type=$ErrorType;source=$Source;id="$runId-$safeErrorType"}|ConvertTo-Json -Compress
$logEvent=Join-Path $RootDir "ai-infra\scripts\log-event.ps1";if(Test-Path $logEvent){& pwsh -File $logEvent -Type "failure.created" -Ok:$false -DataJson $dataJson}
Write-Host "[failure] $runId-$safeErrorType";exit 0
