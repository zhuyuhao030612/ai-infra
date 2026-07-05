# gen-lesson.ps1
param([string]$ErrorMessage="",[string]$Source="",[string]$FromRun="",[string[]]$Tags=@(),[string]$RootDir=$(if($env:CLAUDE_PROJECT_DIR){$env:CLAUDE_PROJECT_DIR}else{"D:\Code"}))
Set-StrictMode -Version 2.0;$ErrorActionPreference="Continue"
function Get-Prop{param($o,$n,$d=$null)if($null-eq$o){return$d};$p=$o.PSObject.Properties[$n];if($null-eq$p){return$d};return$p.Value}
function Redact-Text{param($t)if(-not$t){return $t};$t=$t -replace '(?i)(password|token|secret|key|authorization)\s*[=:]\s*\S+','$1=[REDACTED]';$t=$t -replace '\bBearer\s+[A-Za-z0-9._~+/=-]+','Bearer [REDACTED]';$t=$t -replace '([A-Za-z0-9_\-]{40,})','[TOKEN_REDACTED]';return $t}
$RootDir=[IO.Path]::GetFullPath($RootDir)
$LessonsDir=Join-Path $RootDir "ai-infra\data\lessons";New-Item -ItemType Directory -Force -Path $LessonsDir|Out-Null
$errorDesc=$ErrorMessage
if($FromRun -and (Test-Path $FromRun)){$ef=Join-Path $FromRun "error.txt";if(Test-Path $ef){$errorDesc=Get-Content $ef -Raw -Encoding UTF8};if(-not$errorDesc){$errorDesc="Failure: $FromRun"}}
if(-not$errorDesc){Write-Host "Usage: -ErrorMessage";exit 1}
$errorDesc=Redact-Text $errorDesc;$Source=Redact-Text $Source
$firstLine=($errorDesc -split "\r?\n")[0].Trim();if($firstLine.Length -gt 80){$firstLine=$firstLine.Substring(0,80)}
$maxId=0;Get-ChildItem (Join-Path $LessonsDir "L*-*.md") -EA SilentlyContinue|ForEach-Object{if($_.Name -match "^L(\d+)"){$id=[int]$Matches[1];if($id -gt $maxId){$maxId=$id}}}
$nextId="L{0:D3}" -f ($maxId+1)
$safeName=$firstLine -replace "[\W]+","-" -replace "-{2,}","-" -replace "^-|-$",""
$lessonFile=Join-Path $LessonsDir "$nextId-$safeName.md"
$ts=Get-Date -Format "yyyy-MM-dd"
$title=$firstLine
@"
---
title: $title
date: $ts
source: $Source
status: draft
---
# $firstLine
[TODO]
$errorDesc
"@|Out-File $lessonFile -Encoding UTF8
Write-Host "[lesson] ${nextId}: ${firstLine}";exit 0
