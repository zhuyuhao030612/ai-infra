# self-loop.ps1 — 自驱循环：查队列、分配任务、不空转
# Claude Code 全权接管时调用。永不主动停下，除非老板打断。

param([switch]$DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$OllamaBin = "C:\Users\ZHUYU\AppData\Local\Programs\Ollama\ollama.exe"
$Model = "qwen2.5-coder:7b"
$TopicsFile = "D:\Code\ai-infra\data\learning-queue.txt"
$LearningLog = "D:\Code\ai-infra\data\learning-log.jsonl"

# 学习队列（无限循环的主题列表）
$defaultTopics = @(
    "PowerShell 7.4 新特性 脚本优化 2026",
    "Windows Terminal 高级配置 profile.json",
    "Git 高级操作 rebase bisect worktree",
    "Docker Compose 生产最佳实践 2026",
    "Node.js 24 新特性 性能优化",
    "Python 3.14 free-threading GIL 使用场景",
    "Playwright 自动化测试 设计模式 Page Object",
    "WSL2 性能调优 磁盘 IO 内存",
    "Windows 安全策略 零信任 2026",
    "Tailscale 网络拓扑 高级路由"
)

# 1) 检查当前资源状态
Write-Host "=== 自驱循环 ===" -ForegroundColor Cyan
$ollamaRunning = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
$gptReady = (Get-Content "D:\Code\ai-pipeline\gpt-queue\server-status.json" -ErrorAction SilentlyContinue | ConvertFrom-Json).ready
Write-Host "Ollama: $(if($ollamaRunning){'运行中'}else{'未运行'})"
Write-Host "GPT管道: $(if($gptReady){'空闲'}else{'忙碌或离线'})"

# 2) 如果 Ollama 空闲，分配学习任务
if ($ollamaRunning) {
    # 读取队列（如果文件不存在就创建）
    if (-not (Test-Path $TopicsFile)) {
        $defaultTopics | Set-Content $TopicsFile -Encoding UTF8
    }
    $queue = Get-Content $TopicsFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' }

    if ($queue.Count -eq 0) {
        $defaultTopics | Set-Content $TopicsFile -Encoding UTF8
        $queue = $defaultTopics
    }

    # 取第一个主题
    $topic = $queue[0]
    $remaining = $queue[1..($queue.Count-1)]
    $remaining | Set-Content $TopicsFile -Encoding UTF8

    Write-Host "`n=== Ollama 分配任务: $topic ===" -ForegroundColor Yellow

    # 让 Ollama 提取对 Claude Code 有用的知识
    $prompt = @"
你是一个为Claude Code AI Agent提取学习笔记的助手。主题: $topic
请列出：
1. 5个最重要的知识点（简洁，每条1-2句）
2. 2条实践建议（Claude Code Agent可以直接用的）
3. 1条常见陷阱（容易犯的错）
用JSON格式输出: {"topic":"$topic","knowledge":["...","..."],"practices":["...","..."],"pitfalls":["..."]}
"@

    if (-not $DryRun) {
        $result = $prompt | & $OllamaBin run $Model 2>&1
        $result = $result -replace '\x1b\[[0-9;]*[a-zA-Z]', ''

        # 记录学习日志
        $logEntry = @{
            timestamp = (Get-Date -Format 'o')
            topic = $topic
            model = $Model
            result = $result
        } | ConvertTo-Json -Compress
        $logEntry | Add-Content $LearningLog -Encoding UTF8

        # 如果 GPT 管道空闲，送去审核
        if ($gptReady) {
            Write-Host "`n=== GPT-5.5 审核 ===" -ForegroundColor Yellow
            $gptPrompt = "审核Ollama对[$topic]的学习笔记。过滤不准确的，补充遗漏的重要信息，优化为最终版。原始: $result"
            pwsh -NoLogo -File "D:\Code\ai-infra\scripts\gpt-ask.ps1" -Prompt $gptPrompt -TimeoutSec 180
        }

        # 存档
        $slug = $topic -replace '[^\w]+','-' -replace '-+','-'
        $file = "C:\Users\ZHUYU\.claude\projects\D--Code\memory\learn-$slug.md"
        @"
---
name: $slug
description: $topic
metadata:
  type: reference
  source: self-loop
  date: $(Get-Date -Format 'yyyy-MM-dd')
---
$result
"@ | Set-Content $file -Encoding UTF8

        Write-Host "`n已存档: $file" -ForegroundColor Green
        Write-Host "剩余队列: $($remaining.Count) 个主题" -ForegroundColor Cyan
    }
}

Write-Host "`n=== 自驱循环完成 ===" -ForegroundColor Cyan
