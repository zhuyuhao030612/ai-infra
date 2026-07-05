# learn.ps1 — Ollama预处理→GPT审核→存档
param([string]$Search,[string]$Text,[switch]$NoGPT,[string]$Tag="auto-learned",[int]$TimeoutSec=240,[string]$RootDir=$(if($env:CLAUDE_PROJECT_DIR){$env:CLAUDE_PROJECT_DIR}else{"D:\Code"}))
Set-StrictMode -Version 2.0;$ErrorActionPreference="Continue"
function Get-Prop{param($o,$n,$d=$null)if($null-eq$o){return $d};$p=$o.PSObject.Properties[$n];if($null-eq$p){return $d};return $p.Value}
$RootDir=[IO.Path]::GetFullPath($RootDir);$MemDir=Join-Path $RootDir "memory";New-Item -ItemType Directory -Force -Path $MemDir|Out-Null
$OllamaBin=if($env:OLLAMA_BIN){$env:OLLAMA_BIN}else{"ollama"};$Model="qwen2.5-coder:7b"
$rawText="";if($Search){$rawText="SEARCH_TOPIC: $Search"}elseif($Text){$rawText=$Text}else{Write-Host "用法: -Search <query> 或 -Text <内容>";exit 1}
$prompt=@"
提取关键知识点。输出JSON: {"points":[{"content":"...","type":"knowledge|experience|tool|pattern","tags":["tag1"]}]}
内容: $rawText
"@
$ollamaRaw=$prompt|& $OllamaBin run $Model 2>&1;$ollamaJson=(($ollamaRaw -join "`n") -replace '\x1b\[[0-9;]*[a-zA-Z]','')
$finalJson=$ollamaJson
if(-not $NoGPT){$gptAsk=Join-Path $RootDir "ai-infra\scripts\gpt-ask.ps1";if(Test-Path $gptAsk){$gptPrompt="审核优化知识点JSON: $ollamaJson";$gptResult=& pwsh -NoLogo -File $gptAsk -Prompt $gptPrompt -TimeoutSec $TimeoutSec 2>&1;if($LASTEXITCODE -eq 0){$finalJson=($gptResult -join "`n")}}}
$slug=if($Search){$Search -replace '[^\w]+','-' -replace '-+','-'}else{"learn-$((Get-Date).ToString('HHmmss'))"};if([string]::IsNullOrWhiteSpace($slug)){$slug="learn-$((Get-Date).ToString('HHmmss'))"}
$file=Join-Path $MemDir "$slug.md"
@"
---name: $slugdescription: $Search学习笔记date: $(Get-Date -Format 'yyyy-MM-dd')tag: $Tag---
# $Search
$finalJson
"@|Set-Content -LiteralPath $file -Encoding UTF8
Write-Host "archived: $file";exit 0
