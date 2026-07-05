# GPT-5.5 safe queue client v5 — HTTP pipeline
param(
 [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Prompt,
 [ValidateRange(10,86400)][int]$TimeoutSec=1800,
 [switch]$NoCache,
 [switch]$NoRedact,
 [ValidatePattern('^[A-Za-z0-9._-]{1,50}$')][string]$Mode='ask',
 [string]$RootDir=$(if($env:AI_ROOT){$env:AI_ROOT}else{'D:\Code'})
)
Set-StrictMode -Version Latest

# AI Runtime guard — hard preflight gate
$guardModule = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib') 'AIRuntime.psm1'
if (Test-Path $guardModule) {
  Import-Module $guardModule -Force -ErrorAction SilentlyContinue
  Assert-PreflightGate | Out-Null
}

# UTF-8 output encoding — preserves base64, CJK, and special characters through stdout
try {
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [Console]::OutputEncoding = $utf8NoBom
  [Console]::InputEncoding = $utf8NoBom
  $PSDefaultParameterValues['*:Encoding'] = 'utf8'
} catch {}
$ErrorActionPreference='Stop'

$RootDir=[IO.Path]::GetFullPath($RootDir)
$PipelineDir=if($env:GPT55_PIPELINE_DIR){[IO.Path]::GetFullPath($env:GPT55_PIPELINE_DIR)}else{Join-Path $RootDir 'ai-pipeline'}
$InfraDir=if($env:AI_INFRA_DIR){[IO.Path]::GetFullPath($env:AI_INFRA_DIR)}else{Join-Path $RootDir 'ai-infra'}
$CacheDir=Join-Path $PipelineDir 'gpt-cache'
New-Item -ItemType Directory -Force -Path $CacheDir|Out-Null

function Redact-Text([string]$s){
 if($null -eq $s){return ''}
 $s=$s -replace '(?i)(password|passwd|pwd|pass|token|secret|api[_-]?key|authorization)\s*[=:]\s*[^\s,;}]+','$1=[REDACTED]'
 $s=$s -replace '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+','Bearer [REDACTED]'
 $s=$s -replace '([A-Za-z0-9_\-]{48,})','[TOKEN_REDACTED]'
 $s=$s -replace '\b(?:\d{1,3}\.){3}\d{1,3}\b','[IP_REDACTED]'
 return $s
}
function Sha256Hex([string]$s){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s))|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()}
}
function Write-TextAtomic([string]$Path,[string]$Text){
 $dir=Split-Path -Parent $Path; New-Item -ItemType Directory -Force -Path $dir|Out-Null
 $tmp=Join-Path $dir ('.{0}.{1}.{2}.tmp' -f (Split-Path -Leaf $Path),$PID,[Guid]::NewGuid().ToString('N'))
 try{Set-Content -LiteralPath $tmp -Value $Text -Encoding UTF8 -NoNewline; Move-Item -LiteralPath $tmp -Destination $Path -Force}catch{Remove-Item $tmp -Force -EA SilentlyContinue; throw}
}
function Write-JsonAtomic([string]$Path,$Data,[int]$Depth=8){Write-TextAtomic $Path (($Data|ConvertTo-Json -Depth $Depth)+[Environment]::NewLine)}
function Log-Event([string]$Type,[bool]$Ok,$Data){
 $s=Join-Path $InfraDir 'scripts\log-event.ps1'; if(!(Test-Path -LiteralPath $s)){return}
 try{& pwsh -NoLogo -NoProfile -File $s -Type $Type -Ok:$Ok -DataJson ($Data|ConvertTo-Json -Depth 8 -Compress)|Out-Null}catch{Write-Warning ('log-event failed: '+(Redact-Text $_.Exception.Message))}
}

$clean=if($NoRedact){$Prompt}else{Redact-Text $Prompt}
$cacheFile=$null
if(!$NoCache){
 $cacheFile=Join-Path $CacheDir ((Sha256Hex "gpt55|v5|mode=$Mode|prompt=$clean")+'.json')
 if(Test-Path -LiteralPath $cacheFile){
 try{$c=Get-Content $cacheFile -Raw -Encoding UTF8|ConvertFrom-Json; if($c.response -and ([DateTime]::Now-[DateTime]$c.timestamp).TotalHours -lt 1){Write-Output ([string]$c.response); exit 0}}catch{Remove-Item $cacheFile -Force -EA SilentlyContinue}
 }
}

# Submit job via HTTP POST /ask
$askUri='http://127.0.0.1:3000/ask'
$req=[ordered]@{prompt=$clean;timeout_sec=$TimeoutSec;mode=$Mode}
try{
  $submitted=Invoke-RestMethod `
    -Method Post `
    -Uri $askUri `
    -ContentType 'application/json; charset=utf-8' `
    -Body ($req|ConvertTo-Json -Depth 8 -Compress) `
    -TimeoutSec ([Math]::Max(10,$TimeoutSec)) `
    -ErrorAction Stop
  $jobId=if($submitted.id){[string]$submitted.id}elseif($submitted.job_id){[string]$submitted.job_id}else{''}
  if([string]::IsNullOrWhiteSpace($jobId)){throw 'POST /ask returned no job id'}
}catch{
  Log-Event 'gpt.ask' $false ([ordered]@{error='submit_failed';detail=(Redact-Text $_.Exception.Message)})
  Write-Output 'GPT_UNAVAILABLE'; exit 3
}
Write-Host "[gpt-ask] $jobId -> HTTP queue"

# Poll for result
$start=Get-Date
while($true){
 $elapsed=([DateTime]::Now-$start).TotalSeconds
 if($elapsed -gt $TimeoutSec){
  Log-Event 'gpt.ask' $false ([ordered]@{duration_sec=$TimeoutSec;error='timeout';id=$jobId})
  Write-Output 'GPT_UNAVAILABLE'; exit 124
 }

 try{
  $r=Invoke-RestMethod `
    -Method Get `
    -Uri ("http://127.0.0.1:3000/job/{0}" -f [Uri]::EscapeDataString($jobId)) `
    -TimeoutSec 5 `
    -ErrorAction Stop
  $state=[string]$r.state

  switch($state){
   'pending' { break }
   'running' { break }
   'succeeded' {
     $response=[string]$r.result
     if([string]::IsNullOrWhiteSpace($response) -or $response -eq 'GPT_UNAVAILABLE'){
       Log-Event 'gpt.ask' $false ([ordered]@{error='empty_result';id=$jobId})
       Write-Output 'GPT_UNAVAILABLE'; exit 3
     }
     $sec=[Math]::Round(([DateTime]::Now-$start).TotalSeconds,1)
     if($cacheFile){try{Write-JsonAtomic $cacheFile ([ordered]@{timestamp=(Get-Date -Format 'o');response=$response})}catch{}}
     Log-Event 'gpt.ask' $true ([ordered]@{duration_sec=$sec;id=$jobId;prompt_len=$Prompt.Length;response_len=$response.Length})
     Write-Host "[gpt-ask] $jobId done in ${sec}s"; Write-Output ($response.Trim()); exit 0
   }
   'retryable_failed' {
     Log-Event 'gpt.ask' $false ([ordered]@{error='retryable_failed';id=$jobId})
     Write-Output 'GPT_UNAVAILABLE'; exit 3
   }
   'dead_letter' {
     Log-Event 'gpt.ask' $false ([ordered]@{error='dead_letter';id=$jobId})
     Write-Output 'GPT_UNAVAILABLE'; exit 3
   }
   default { throw "unknown job state: $state" }
  }
 }catch{
  if($elapsed -gt $TimeoutSec){ continue }
  Log-Event 'gpt.ask' $false ([ordered]@{error='poll_failed';id=$jobId;detail=(Redact-Text $_.Exception.Message)})
 }

 Start-Sleep -Seconds 3
}
