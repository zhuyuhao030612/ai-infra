# 日常操作手册

## 每日

```powershell
# 新任务（自动执行）
pwsh -File D:\Code\ai-infra\scripts\new-run.ps1 -Task "任务描述"
pwsh -File D:\Code\ai-infra\scripts\lessons-search.ps1 -Task "任务描述"

# 改动后
pwsh -File D:\Code\local-agent\scripts\verify.ps1
pwsh -File D:\Code\ai-infra\smoke\run-all.ps1
```

## 每周

```powershell
pwsh -File D:\Code\ai-infra\scripts\weekly-health.ps1
```

## 每月

```powershell
# 试运行
pwsh -File D:\Code\ai-infra\scripts\cleanup-runs.ps1 -Days 30
# 确认无误后
pwsh -File D:\Code\ai-infra\scripts\cleanup-runs.ps1 -Days 30 -Apply
# 复盘 deprecated lessons
```

## 重大改动前

```powershell
pwsh -File D:\Code\ai-infra\smoke\test-safety.ps1
```

## 快速诊断

```powershell
# 系统健康
curl http://127.0.0.1:9000/health
curl http://127.0.0.1:9000/status

# 管道状态
cat D:\Code\ai-pipeline\gpt55-output.log | tail -3

# 看门狗
cat D:\Code\local-agent\logs\watchdog.log | tail -3

# 事件
cat D:\Code\ai-infra\logs\events.jsonl | tail -5

# Token 位置
cat D:\Code\local-agent\.env
```

## 发 prompt 到 GPT-5.5

```powershell
pwsh -File D:\Code\ai-infra\scripts\gpt-ask.ps1 -Prompt "你的问题" -TimeoutSec 120
```
