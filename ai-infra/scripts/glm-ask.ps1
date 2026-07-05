# glm-ask.ps1 — GLM-5.2 shadow pipeline
param([Parameter(Mandatory=$true)][string]$Prompt,[int]$TimeoutSec=120,[switch]$Thinking,[string]$RootDir=$(if($env:CLAUDE_PROJECT_DIR){$env:CLAUDE_PROJECT_DIR}else{"D:\Code"}))
Set-StrictMode -Version 2.0

# AI Runtime guard — hard preflight gate
$guardModule = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib') 'AIRuntime.psm1'
if (Test-Path $guardModule) {
  Import-Module $guardModule -Force -ErrorAction SilentlyContinue
  Assert-PreflightGate | Out-Null
}

$ErrorActionPreference="Continue"
function Get-Prop{param($o,$n,$d=$null)if($null-eq$o){return $d};$p=$o.PSObject.Properties[$n];if($null-eq$p){return $d};return $p.Value}
$RootDir=[IO.Path]::GetFullPath($RootDir);$PipelineDir=Join-Path $RootDir "ai-pipeline";New-Item -ItemType Directory -Force -Path $PipelineDir|Out-Null
$LocalEnv=Join-Path $PipelineDir ".env.ps1";if(Test-Path $LocalEnv){try{.$LocalEnv}catch{}}
$ApiKey=if($env:GLM_API_KEY){$env:GLM_API_KEY}elseif($env:ZHIPU_API_KEY){$env:ZHIPU_API_KEY}elseif($env:ZAI_API_KEY){$env:ZAI_API_KEY}else{""}
if([string]::IsNullOrWhiteSpace($ApiKey)){Write-Output "GLM_UNAVAILABLE: No API key";exit 1}
$Endpoint="https://open.bigmodel.cn/api/paas/v4/chat/completions";$ModelId="glm-5.2"
$messages=@(@{role="user";content=$Prompt});$reqBody=[ordered]@{model=$ModelId;messages=$messages;max_tokens=65536;temperature=1.0;stream=$false}
if($Thinking){$reqBody.thinking=@{type="enabled"}}
$body=$reqBody|ConvertTo-Json -Depth 6 -Compress;$sw=[Diagnostics.Stopwatch]::StartNew()
try{
    $response=Invoke-WebRequest -Uri $Endpoint -Method Post -Headers @{"Authorization"="Bearer $ApiKey";"Content-Type"="application/json"} -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
    $sw.Stop();$result=$response.Content|ConvertFrom-Json
    $choices=@(Get-Prop $result "choices" @());if($choices.Count -eq 0){throw "GLM response missing choices"}
    $message=Get-Prop $choices[0] "message" $null;$text=[string](Get-Prop $message "content" "")
    if([string]::IsNullOrWhiteSpace($text)){throw "GLM response missing message.content"}
    $reasoning=[string](Get-Prop $message "reasoning_content" "")
    $usage=Get-Prop $result "usage" $null;$promptTokens=[int](Get-Prop $usage "prompt_tokens" 0);$completionTokens=[int](Get-Prop $usage "completion_tokens" 0)
    $costIn=($promptTokens/1000000)*1.40;$costOut=($completionTokens/1000000)*4.40;$costTotal=[math]::Round($costIn+$costOut,4)
    $outputPath=Join-Path $PipelineDir "from-glm52.md";$thinkingBlock=if($reasoning){"`n### 思考过程`n$reasoning`n"}else{""}
    $output="# <- GLM-5.2 (Shadow)> $((Get-Date).ToString('o')) | $ModelId | $($sw.ElapsedMilliseconds)ms | `$${costTotal}---`n${thinkingBlock}$text"
    $output|Out-File -LiteralPath $outputPath -Encoding UTF8
    Write-Host "[glm-ask] done in $($sw.ElapsedMilliseconds)ms | tokens: in=$promptTokens out=$completionTokens | cost=`$${costTotal}"
    if($reasoning){Write-Host "[glm-ask] reasoning: $($reasoning.Length) chars"}
    Write-Output $text;exit 0
}catch{$sw.Stop();Write-Output "GLM_UNAVAILABLE: $($_.Exception.Message)";exit 1}
