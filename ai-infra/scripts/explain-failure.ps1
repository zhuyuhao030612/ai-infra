# explain-failure.ps1 — failure diagnostic
param([switch]$Latest,[string]$Id="",[string]$RootDir=$(if($env:CLAUDE_PROJECT_DIR){$env:CLAUDE_PROJECT_DIR}else{"D:\Code"}))
Set-StrictMode -Version 2.0;$ErrorActionPreference="Continue"
function Get-Prop{param($o,$n,$d=$null)if($null-eq$o){return$d};$p=$o.PSObject.Properties[$n];if($null-eq$p){return$d};return$p.Value}
$RootDir=[IO.Path]::GetFullPath($RootDir)
$FailuresDir=Join-Path $RootDir "ai-infra\failures"
$LessonsSearch=Join-Path $RootDir "ai-infra\scripts\lessons-search.ps1"
$target=$null
if($Id){$target=Get-ChildItem -Path (Join-Path $FailuresDir "$Id*") -Directory -EA SilentlyContinue|Select-Object -First 1}
elseif($Latest -or -not $Id){$target=Get-ChildItem -Path $FailuresDir -Directory -EA SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1}
if(-not $target){Write-Host "no failure found";exit 1}
Write-Host "=== Failure: $($target.Name) ==="
$manifest=$null;$errorType="unknown";$summary=""
$manifestPath=Join-Path $target.FullName "manifest.json"
if(Test-Path $manifestPath){try{$manifest=Get-Content $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json;$errorType=[string](Get-Prop $manifest "error_type" "unknown");$summary=[string](Get-Prop $manifest "summary" "");Write-Host "source: $(Get-Prop $manifest 'source' '') type: $errorType"}catch{$manifest=$null}}
$errorFile=Join-Path $target.FullName "error.txt"
if(Test-Path $errorFile){$errorText=Get-Content $errorFile -Raw -Encoding UTF8;$maxLen=[Math]::Min(500,$errorText.Length);Write-Host $errorText.Substring(0,$maxLen)}
Write-Host "Diagnosis: $errorType"
if($errorType -eq "selector_not_found"){Write-Host "pipeline selector not found. Check login state and DOM."}
elseif($errorType -eq "timeout"){Write-Host "timeout. Check network and pipeline logs."}
else{Write-Host "unknown. Check evidence at $($target.FullName)"}
if(Test-Path $LessonsSearch){$lr=& pwsh -File $LessonsSearch -Task "$errorType $summary" 2>&1|Select-String "得分";if($lr){$lr|ForEach-Object{Write-Host $_}}}
exit 0
