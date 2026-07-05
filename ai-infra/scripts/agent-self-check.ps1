<#
.SYNOPSIS
任务开始时运行：把"当前任务"匹配到建议能力。
不是死关键词：使用 registry 行解析 + 中英意图画像 + 字符 ngram 相似度 + 规则信号。
.USAGE
pwsh D:\Code\ai-infra\scripts\agent-self-check.ps1 -Task "我要操作网页表单"
pwsh D:\Code\ai-infra\scripts\agent-self-check.ps1 -Task "修复多文件 bug 并跑测试" -Top 8
pwsh D:\Code\ai-infra\scripts\agent-self-check.ps1 -Task "截图看不懂" -Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Task,
    [string]$RegistryPath = "",
    [int]$Top = 8,
    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Normalize-Text {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $t = $Text.ToLowerInvariant()
    $t = $t -replace '[，。！？；：、""''（）【】《》]', ' '
    $t = $t -replace '[^\p{L}\p{Nd}_\-\.:/\\]+', ' '
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-CharNgrams {
    param([string]$Text, [int]$N=2)
    $t = Normalize-Text $Text
    $set = [System.Collections.Generic.HashSet[string]]::new()
    if ($t.Length -le $N) { if ($t) { [void]$set.Add($t) }; return $set }
    for ($i=0; $i -le $t.Length-$N; $i++) {
        $g = $t.Substring($i, $N)
        if (-not [string]::IsNullOrWhiteSpace($g)) { [void]$set.Add($g) }
    }
    return $set
}

function Get-TokenSet {
    param([string]$Text)
    $t = Normalize-Text $Text
    $set = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($tok in ($t -split '\s+')) { if ($tok.Length -ge 2) { [void]$set.Add($tok) } }
    return $set
}

function Jaccard {
    param([System.Collections.Generic.HashSet[string]]$A, [System.Collections.Generic.HashSet[string]]$B)
    if ($A.Count -eq 0 -or $B.Count -eq 0) { return 0.0 }
    $inter = 0; foreach ($x in $A) { if ($B.Contains($x)) { $inter++ } }
    $union = $A.Count + $B.Count - $inter
    if ($union -le 0) { return 0.0 } else { return [double]$inter / [double]$union }
}

function Contains-Any {
    param([string]$Text, [string[]]$Terms)
    foreach ($term in $Terms) { if ($Text -match [regex]::Escape($term)) { return $true } }
    return $false
}

function Parse-Registry {
    param([string]$Path)
    $items = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path)) { return $items }
    $section = "unknown"
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match '^##+\s+(.+)$') { $section = $Matches[1].Trim(); continue }
        if ($line -notmatch '^TRIGGER:\s*(.+?)\s*\|\s*USE:\s*(.+?)\s*\|\s*CALL:\s*(.+?)\s*\|\s*FALLBACK:\s*(.+?)\s*$') { continue }
        $trigger = $Matches[1].Trim(); $use = $Matches[2].Trim(); $call = $Matches[3].Trim(); $fallback = $Matches[4].Trim()
        $text = "$section $trigger $use $call $fallback"
        $items.Add([pscustomobject]@{section=$section; trigger=$trigger; use=$use; call=$call; fallback=$fallback; text=$text}) | Out-Null
    }
    return $items
}

# 意图画像
$IntentProfiles = @(
    @{id="browser"; label="浏览器/网页"; weight=1.35; phrases=@("网页 浏览器 DOM 表单 URL 点击 登录 下拉 链接 console network upload tab navigate screenshot playwright")}
    @{id="desktop"; label="桌面/Windows GUI"; weight=1.35; phrases=@("桌面 Windows 窗口 GUI 屏幕 点击 控件 OCR 截图 鼠标 键盘 快捷键 应用程序 远程桌面 UI树 automation")}
    @{id="code"; label="代码/Bug/重构"; weight=1.25; phrases=@("代码 bug 修复 报错 测试失败 重构 函数 类 变量 patch diff pytest lint build 多文件 模块")}
    @{id="file"; label="文件/搜索"; weight=1.15; phrases=@("文件 查找 搜索 grep glob 读取 修改 替换 新建 删除 批量 配置 日志")}
    @{id="memory"; label="记忆/改错本"; weight=1.25; phrases=@("以前 上次 记忆 经验 改错本 踩坑 mistake lesson memory mem0 规则")}
    @{id="learning"; label="学习/研究"; weight=1.25; phrases=@("学习 研究 搜资料 最新 新闻 官方文档 WebSearch WebFetch 提取 审核 入库")}
    @{id="security"; label="安全/权限"; weight=1.45; phrases=@("安全 危险 删除 凭证 token secret key env pem ssh 外发 权限 注入 审计 guard")}
    @{id="ops"; label="运维/服务"; weight=1.2; phrases=@("健康 检查 服务 端口 9000 9100 11434 Ollama Agent Hub local-agent Docker WSL 诊断")}
    @{id="ai"; label="AI模型/外脑"; weight=1.2; phrases=@("模型 GLM GPT Ollama 豆包 DeepSeek agent-ask gpt-ask glm-ask panel 多模型 审计 视觉")}
    @{id="task"; label="任务/证据/收尾"; weight=1.2; phrases=@("任务 开始 完成 收尾 证据 evidence close-run finish-task ledger stop gate 失败 阻塞")}
    @{id="media"; label="媒体/OCR/视频"; weight=1.1; phrases=@("图片 视频 音频 媒体 OCR 字幕 剪辑 ffmpeg pillow opencv")}
)

# 规则信号
$SignalRules = @(
    @{name="external-risk"; terms=@("外发","api","GLM","GPT","OpenRouter","Groq","豆包","模型"); boost="security"; score=0.25}
    @{name="destructive"; terms=@("删除","清空","reset","prune","unregister","force push","Remove-Item","rm -rf"); boost="security"; score=0.35}
    @{name="visual"; terms=@("截图","看屏幕","OCR","画面","视觉","图像","屏幕"); boost="desktop"; score=0.25}
    @{name="web"; terms=@("网页","浏览器","URL","DOM","表单","登录","链接"); boost="browser"; score=0.30}
    @{name="test"; terms=@("测试","pytest","lint","build","报错","失败"); boost="code"; score=0.20}
    @{name="memory"; terms=@("以前","上次","记住","改错本","经验","踩坑"); boost="memory"; score=0.30}
    @{name="finish"; terms=@("完成","收尾","证据","结束","验收"); boost="task"; score=0.25}
)

if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { "D:\Code" }
    $RegistryPath = Join-Path $root "CAPABILITY_REGISTRY.md"
}
$registry = Parse-Registry -Path $RegistryPath
if ($registry.Count -eq 0) {
    $msg = "Registry not found or empty: $RegistryPath"
    if ($Json) { [pscustomobject]@{ok=$false; error=$msg} | ConvertTo-Json -Depth 4 } else { Write-Host $msg -ForegroundColor Red }
    exit 1
}

$taskNorm = Normalize-Text $Task
$taskTokens = Get-TokenSet $Task
$taskNgrams = Get-CharNgrams $Task 2

# 意图分
$intentScores = @{}
foreach ($profile in $IntentProfiles) {
    $pT = Get-TokenSet ($profile.phrases -join " ")
    $pN = Get-CharNgrams ($profile.phrases -join " ") 2
    $score = (Jaccard $taskTokens $pT) * 0.55 + (Jaccard $taskNgrams $pN) * 0.45
    $score = $score * [double]$profile.weight
    $intentScores[$profile.id] = $score
}
foreach ($rule in $SignalRules) {
    if (Contains-Any -Text $Task -Terms $rule.terms) {
        if ($intentScores.ContainsKey($rule.boost)) { $intentScores[$rule.boost] += [double]$rule.score }
    }
}
$topIntents = $intentScores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3

# Registry 行评分
$results = [System.Collections.Generic.List[object]]::new()
foreach ($item in $registry) {
    $iT = Get-TokenSet $item.text; $iN = Get-CharNgrams $item.text 2
    $score = (Jaccard $taskTokens $iT) * 0.50 + (Jaccard $taskNgrams $iN) * 0.35
    $sectionNorm = Normalize-Text $item.section
    foreach ($intent in $topIntents) {
        $v = [double]$intent.Value; if ($v -le 0) { continue }
        $sb = 0.0
        switch ($intent.Key) {
            "browser" { if ($sectionNorm -match '浏览器|网页|dom') { $sb = 0.18 } }
            "desktop" { if ($sectionNorm -match '桌面|windows|gui|屏幕') { $sb = 0.18 } }
            "code" { if ($sectionNorm -match '代码|测试|重构') { $sb = 0.18 } }
            "file" { if ($sectionNorm -match '文件|搜索') { $sb = 0.16 } }
            "memory" { if ($sectionNorm -match '记忆|改错|经验') { $sb = 0.18 } }
            "learning" { if ($sectionNorm -match '学习|研究|资料') { $sb = 0.18 } }
            "security" { if ($sectionNorm -match '安全|权限|外发') { $sb = 0.22 } }
            "ops" { if ($sectionNorm -match '运维|健康|服务') { $sb = 0.16 } }
            "ai" { if ($sectionNorm -match 'ai模型|agent hub|外脑') { $sb = 0.16 } }
            "task" { if ($sectionNorm -match '任务|证据|收尾|hook') { $sb = 0.16 } }
            "media" { if ($sectionNorm -match '媒体|ocr|视频') { $sb = 0.14 } }
        }
        $score += $sb * [Math]::Min(1.0, $v * 4.0)
    }
    # 精确包含触发词
    $triggerParts = $item.trigger -split '[/,,， ]+' | Where-Object { $_.Trim().Length -ge 2 }
    foreach ($p in $triggerParts) {
        if ($p.Trim() -and $taskNorm.Contains((Normalize-Text $p.Trim()))) { $score += 0.12 }
    }
    if ($score -gt 0.015) {
        $results.Add([pscustomobject]@{score=[Math]::Round($score,4); section=$item.section; trigger=$item.trigger; use=$item.use; call=$item.call; fallback=$item.fallback}) | Out-Null
    }
}
$ranked = $results | Sort-Object score -Descending | Select-Object -First $Top

# 安全提醒
$warnings = [System.Collections.Generic.List[string]]::new()
if (Contains-Any -Text $Task -Terms @(".env","token","secret","key","pem","ssh","凭证","外发","api")) { $warnings.Add("敏感/外发风险：先 security-gate / redact / pretool-guard") | Out-Null }
if (Contains-Any -Text $Task -Terms @("删除","reset","prune","unregister","Remove-Item","rm -rf","force push")) { $warnings.Add("破坏性操作：必须 ps-guard，必要时 waiver") | Out-Null }
if (Contains-Any -Text $Task -Terms @("修改","修复","重构","写入","Edit","Write")) { $warnings.Add("修改意图：结束前 evidence-check + close-run") | Out-Null }

$output = [pscustomobject]@{
    ok = $true; task = $Task; registry = $RegistryPath
    top_intents = @(foreach ($i in $topIntents) {
        $label = ($IntentProfiles | Where-Object { $_.id -eq $i.Key } | Select-Object -First 1).label
        [pscustomobject]@{id=$i.Key; label=$label; score=[Math]::Round([double]$i.Value,4)}
    })
    suggestions = $ranked; warnings = $warnings
    protocol = @("先用建议能力，不要默认 PowerShell","浏览器优先 Playwright；桌面优先 Windows MCP；屏幕兜底 Vision","修改/执行/外发必须经过 Hook 门禁","结束前补测试、证据、close-run")
}

if ($Json) { $output | ConvertTo-Json -Depth 8; exit 0 }

Write-Host "`n=== Agent Self Check ===" -ForegroundColor Cyan
Write-Host "Task: $Task`n"
Write-Host "Top intents:" -ForegroundColor Yellow
foreach ($i in $output.top_intents) { Write-Host ("- {0} ({1}) score={2}" -f $i.label, $i.id, $i.score) }
if ($warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Red
    foreach ($w in $warnings) { Write-Host "- $w" }
}
Write-Host "`nSuggested capabilities:" -ForegroundColor Green
$idx = 1
foreach ($s in $ranked) {
    Write-Host ("{0}. [{1}] score={2}" -f $idx, $s.section, $s.score) -ForegroundColor Green
    Write-Host ("   TRIGGER: {0}" -f $s.trigger)
    Write-Host ("   USE: {0} | CALL: {1}" -f $s.use, $s.call)
    $idx++
}
Write-Host "`nProtocol:" -ForegroundColor Cyan
foreach ($p in $output.protocol) { Write-Host "- $p" }
exit 0
