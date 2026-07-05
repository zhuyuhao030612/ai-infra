# lessons-search.ps1 — experience search
param([string]$Keywords="",[string]$Task="",[switch]$ListAll,[string]$RootDir=$(if($env:CLAUDE_PROJECT_DIR){$env:CLAUDE_PROJECT_DIR}else{"D:\Code"}))
Set-StrictMode -Version 2.0;$ErrorActionPreference="Continue"
function Get-Prop{param($o,$n,$d=$null)if($null-eq$o){return$d};$p=$o.PSObject.Properties[$n];if($null-eq$p){return$d};return$p.Value}
$RootDir=[IO.Path]::GetFullPath($RootDir)
$MemoryDir=Join-Path $RootDir "memory";$LessonsDir=Join-Path $RootDir "ai-infra\data\lessons"
$kwList=@();if($Task){$kwList+=$Task -split '\s+'};if($Keywords){$kwList+=$Keywords -split ','|ForEach-Object{$_.Trim()}}
$kwList=@($kwList|Where-Object{$_ -and $_.Length -gt 1}|Select-Object -Unique)
if($kwList.Count -eq 0 -and -not $ListAll){Write-Host "Usage: -Task 'desc' or -Keywords 'kw'";exit 0}
$sources=@(@{N="mistake-log";P=(Join-Path $MemoryDir "mistake-log.md")},@{N="failure-modes";P=(Join-Path $MemoryDir "agent-failure-modes.md")},@{N="windows-pitfalls";P=(Join-Path $MemoryDir "windows-pitfalls.md")},@{N="pipeline-ops";P=(Join-Path $MemoryDir "gpt55-pipeline-ops.md")})
Get-ChildItem (Join-Path $LessonsDir "L*-*.md") -EA SilentlyContinue|ForEach-Object{$sources+=@{N="lesson:$($_.BaseName)";P=$_.FullName}}
$totalHits=0
foreach($src in $sources){if(-not(Test-Path $src.P)){continue};$c=Get-Content $src.P -Raw -Encoding UTF8;if(-not$c){continue}
  $score=0;foreach($kw in $kwList){if($c -match [regex]::Escape($kw)){$score++}}
  if($score -gt 0){$totalHits++;Write-Host "HIT $($src.N) score=$score";($c -split "`n"|Select-String ([regex]::Escape($kwList[0]))|Select-Object -First 2)|ForEach-Object{Write-Host "  $($_.Line.Trim())"}}}
Write-Host "Total: $totalHits hits";exit 0
