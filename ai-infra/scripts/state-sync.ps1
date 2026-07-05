# 同步 .ai-state/state.json — 唯一状态源
param([string]$RootDir=$(if($env:AI_ROOT){$env:AI_ROOT}else{'D:\Code'}),[string]$AgentHealthUrl='http://127.0.0.1:9000/health')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$RootDir=[IO.Path]::GetFullPath($RootDir)
$StateDir=Join-Path $RootDir '.ai-state'; $RunsDir=Join-Path $StateDir 'runs'; $StateFile=Join-Path $StateDir 'state.json'
$InfraDir=Join-Path $RootDir 'ai-infra'; $PipelineDir=Join-Path $RootDir 'ai-pipeline'
New-Item -ItemType Directory -Force -Path $StateDir,$RunsDir|Out-Null
function Write-JsonAtomic($Path,$Data){
 $dir=Split-Path -Parent $Path; New-Item -ItemType Directory -Force -Path $dir|Out-Null
 $tmp=Join-Path $dir ('.{0}.{1}.{2}.tmp' -f (Split-Path -Leaf $Path),$PID,[Guid]::NewGuid().ToString('N'))
 try{($Data|ConvertTo-Json -Depth 8)+[Environment]::NewLine|Set-Content $tmp -Encoding UTF8 -NoNewline;Move-Item $tmp $Path -Force}catch{Remove-Item $tmp -Force -EA SilentlyContinue;throw}
}
$currentTask=''
$ct=Join-Path $StateDir 'current-task.md'
if(Test-Path $ct){$txt=Get-Content $ct -Raw -Encoding UTF8;$m=[regex]::Match($txt,'(?m)^##\s*目标\s*(?<g>.*)$');$currentTask=($(if($m.Success){$m.Groups['g'].Value}else{($txt -split "`r?`n"|Where-Object{$_.Trim()}|Select-Object -First 1)}) -replace '\s+',' ').Trim()}
$lastSmoke=$null;$smokeLog=Join-Path $InfraDir 'smoke\smoke-history.jsonl'
if(Test-Path $smokeLog){try{$l=Get-Content $smokeLog -Tail 1 -Encoding UTF8;if($l){$lastSmoke=$l|ConvertFrom-Json}}catch{}}
$lastVerify=$null;$eventsLog=Join-Path $InfraDir 'logs\events.jsonl'
if(Test-Path $eventsLog){try{$lastVerify=Get-Content $eventsLog -Tail 100 -Encoding UTF8|ForEach-Object{try{$_|ConvertFrom-Json}catch{$null}}|Where-Object{$null -ne $_ -and $_.type -eq 'verify.run'}|Select-Object -Last 1}catch{}}
$q=Join-Path $PipelineDir 'gpt-queue'
$inbox=@(Get-ChildItem (Join-Path $q 'inbox') -Filter '*.request.json' -File -EA SilentlyContinue).Count
$proc=@(Get-ChildItem (Join-Path $q 'processing') -Filter '*.request.json' -File -EA SilentlyContinue).Count
$failedQ=@(Get-ChildItem (Join-Path $q 'failed') -Directory -EA SilentlyContinue).Count
$failCount=@(Get-ChildItem (Join-Path $InfraDir 'failures') -Directory -EA SilentlyContinue).Count
$healthOk=$false; try{$healthOk=((Invoke-WebRequest $AgentHealthUrl -TimeoutSec 3 -UseBasicParsing).StatusCode -eq 200)}catch{}
$latestRun=Get-ChildItem $RunsDir -Directory -EA SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
# Collect recent run summaries (machine-readable)
$recentRuns = @(Get-ChildItem $RunsDir -Directory -EA SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 5 |
    ForEach-Object {
        $tj = Join-Path $_.FullName "task.json"
        if (Test-Path $tj) {
            try {
                $d = Get-Content $tj -Raw -Encoding UTF8 | ConvertFrom-Json
                [ordered]@{id=$d.id; title=$d.title; status=$d.status; max_level=$d.max_level; created_at=$d.created_at; evidence_count=$(if($d.evidence_count){$d.evidence_count}else{0})}
            } catch { $null }
        } else { $null }
    } | Where-Object { $_ -ne $null })

$new=[ordered]@{current_task=$currentTask;task_status=$(if($currentTask){'running'}else{'idle'});current_run=$(if($latestRun){$latestRun.Name}else{$null});last_smoke=$(if($lastSmoke){@{ok=$lastSmoke.healthy;passed=$lastSmoke.passed;total=$lastSmoke.total;ts=$lastSmoke.timestamp}}else{$null});last_verify=$(if($lastVerify){@{ok=$lastVerify.ok;project=$lastVerify.project;ts=$lastVerify.ts}}else{$null});gpt_queue=@{inbox=$inbox;processing=$proc;failed=$failedQ};failures_count=$failCount;local_agent_ok=$healthOk;recent_runs=$recentRuns;state_machine_version="1.0";updated_at=(Get-Date).ToUniversalTime().ToString('o')}
Write-JsonAtomic $StateFile $new
Write-Host "State synced: $StateFile"
