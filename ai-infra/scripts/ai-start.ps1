# AI Start — 强制任务入口，自动分类 → 输出必须步骤
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Task,[string]$RootDir=$(if($env:AI_ROOT){$env:AI_ROOT}else{'D:\Code'}))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$RootDir=[IO.Path]::GetFullPath($RootDir); $Scripts=Join-Path $RootDir 'ai-infra\scripts'; $Smoke=Join-Path $RootDir 'ai-infra\smoke'
function Q([string]$v){return "'" + ($v -replace "'","''") + "'"}
function AddStep($cmd,$why){$script:mandatory.Add([ordered]@{s=$script:step;cmd=$cmd;why=$why})|Out-Null;$script:step++}
function RunOptional($p,[string[]]$a){if(Test-Path $p){try{& pwsh -NoLogo -NoProfile -File $p @a 2>&1|Write-Host}catch{Write-Host " WARN: $($_.Exception.Message)"}}else{Write-Host " SKIP: $p"}}
Write-Host '╔══════════════════════════════════════╗'
Write-Host '║ AI Task Router ║'
Write-Host '╚══════════════════════════════════════╝'
Write-Host "`n任务: $Task`n"
$types=New-Object System.Collections.Generic.List[string]
if($Task -match '部署|deploy|安装|install|setup|配置|环境|env|PATH|Python|uv|node'){$types.Add('deploy')}
if($Task -match 'GUI|点击|click|输入|type|截图|screenshot|桌面|窗口|window|按钮|button'){$types.Add('gui')}
if($Task -match 'SSH|ssh|远程|remote|RDP|rdp|3389|连接'){$types.Add('remote')}
if($Task -match '安全|security|token|auth|权限|permission|凭据|cookie|secret'){$types.Add('security')}
if($Task -match 'PowerShell|ps1|脚本|script|\.ps1'){$types.Add('powershell')}
if($Task -match 'GPT|gpt|管道|pipeline|queue|队列'){$types.Add('gpt-pipeline')}
if($Task -match 'local-agent|API|路由|router|端点|endpoint'){$types.Add('local-agent')}
if($Task -match '文档|doc|README|RUNBOOK|markdown|md'){$types.Add('docs')}
if($Task -match '删除|delete|remove|覆盖|overwrite|move|kill|exec|执行命令|修改配置|config|settings|\.json|\.ps1'){$types.Add('high-side-effect')}
if($Task -match 'evidence|证据|验证|check|verify'){$types.Add('evidence')}
$filesChanged=0; if(Get-Command git -EA SilentlyContinue){try{$filesChanged=@(& git -C $RootDir diff --name-only 2>$null).Count}catch{}}
if(!$types.Count){$types.Add('code')}; if($filesChanged -ge 3 -and !$types.Contains('multi-file')){$types.Add('multi-file')}
Write-Host "分类: $($types -join ', ')"; Write-Host "改动文件: $filesChanged`n"
Write-Host '── 历史记忆 ──'; RunOptional (Join-Path $Scripts 'memory-search.ps1') @('-Query',"$Task $($types -join ' ')",'-Limit','3'); Write-Host ''
Write-Host '── 成功判据 ──'; Write-Host 'Done when: [请定义完成条件]'; Write-Host 'Verify by: [如何验证]'; Write-Host "Fallback if: [主方案失败的备选]`n"
Write-Host '── 强制步骤（跳过=违规）──'
$mandatory=New-Object System.Collections.Generic.List[object]; $step=1; $qt=Q $Task
AddStep "pwsh -File $(Join-Path $Scripts 'new-run.ps1') -Task $qt" '建立运行目录'
AddStep "pwsh -File $(Join-Path $Scripts 'lessons-search.ps1') -Task $qt" '检索历史故障'
if('deploy' -in $types -or 'powershell' -in $types){AddStep "pwsh -File $(Join-Path $Scripts 'env-probe.ps1') -RootDir $(Q $RootDir)" '部署前必跑环境探测 ⚠️ 禁止跳过'}
if('powershell' -in $types){AddStep "pwsh -File $(Join-Path $Scripts 'ps-guard.ps1') -Path <script>" 'PowerShell 安检 ⚠️ 不过不许交付'}
if('gui' -in $types){AddStep "pwsh -File $(Join-Path $Scripts 'gui-probe.ps1')" 'GUI 探测 ⚠️ 不探测不许盲点';AddStep "node $(Join-Path $RootDir 'ai-pipeline\vision.js') <crop.jpg>" 'Vision 分析 ⚠️ 不定位不许点击';AddStep '(截图 hash 对比验证状态变化)' '反馈验证 ⚠️ 无变化不许继续'}
if($filesChanged -ge 3 -or 'multi-file' -in $types){AddStep "pwsh -File $(Join-Path $Scripts 'impact.ps1') -Files '...'" '3+ 文件影响分析'}
if('security' -in $types -or 'high-side-effect' -in $types){AddStep '发送脱敏方案到 GPT-5.5 复核' '安全审查 ⚠️ 必须外脑确认';AddStep '如涉及 L3+：先 dry-run，再等待人类明确确认；agent 不得自填 risk_ack=true' '人类授权 ⚠️ GPT 复核不是授权';AddStep "pwsh -File $(Join-Path $Smoke 'test-safety.ps1')" 'safety smoke'}
if('high-side-effect' -in $types -or 'evidence' -in $types){AddStep "pwsh -File $(Join-Path $Scripts 'evidence-check.ps1') -Operation validate -Target <目标文件>" '证据驱动检查 ⚠️ 修改前确认目标存在'}
if('remote' -in $types){AddStep '优先 SSH/RDP，GUI 作为最后手段' '不猜环境 ⚠️ 失败两次切方案'}
AddStep "pwsh -File $(Join-Path $RootDir 'local-agent\scripts\verify.ps1')" '代码验证'
AddStep "pwsh -File $(Join-Path $Smoke 'run-all.ps1')" '冒烟测试'
AddStep "pwsh -File $(Join-Path $Scripts 'close-run.ps1') -Run <run-id>" '任务收口'
AddStep "pwsh -File $(Join-Path $Scripts 'state-sync.ps1')" '同步唯一状态源'
foreach($m in $mandatory){$tag=if([string]$m.why -match '⚠️'){'🔒'}else{'✅'};Write-Host "$tag $($m.s). $($m.cmd)";Write-Host " 原因: $($m.why)"}
Write-Host "`n── 刹车规则 ──"
Write-Host ' 同方案失败 2 次 → failure-analysis + GPT'
Write-Host ' GUI 2 次截图无变化 → 停，切方案'
Write-Host ' PS 语法错误 1 次 → ps-guard，不许交付'
Write-Host ' L3+ 无人类确认 → 停'
Write-Host " 10 分钟无进展 → blocker-pack + GPT`n"
$log=Join-Path $Scripts 'log-event.ps1'
if(Test-Path $log){try{& pwsh -NoLogo -NoProfile -File $log -Type 'task.start' -Ok:$true -DataJson ([ordered]@{task=$Task;types=($types -join ',');files_changed=$filesChanged}|ConvertTo-Json -Compress) 2>$null|Out-Null}catch{}}
Write-Host '══════════════════════════════════════'

# A1: Write task_started=true to current.json
try {
    $statePath = Join-Path $RootDir ".claude\run-state\current.json"
    $stateDir = Split-Path -Parent $statePath
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $state = if (Test-Path $statePath) { try { Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [pscustomobject]@{} } } else { [pscustomobject]@{} }
    function Set-SP($o,$n,$v) { if ($o.PSObject.Properties.Name -contains $n) { $o.$n=$v } else { $o|Add-Member -NotePropertyName $n -NotePropertyValue $v -Force } }
    Set-SP $state "task_started" $true
    Set-SP $state "task" $Task
    Set-SP $state "capability_checked" $true
    Set-SP $state "started_at" (Get-Date -Format 'o')
    Set-SP $state "guard_used" $true
    if ($state.PSObject.Properties.Name -notcontains "tests_run") { Set-SP $state "tests_run" $false }
    if ($state.PSObject.Properties.Name -notcontains "evidence_collected") { Set-SP $state "evidence_collected" $false }
    if ($state.PSObject.Properties.Name -notcontains "close_run_done") { Set-SP $state "close_run_done" $false }
    $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-Host "ai-start: task_started=true"
} catch { Write-Host "WARN: state write failed: $($_.Exception.Message)" }
