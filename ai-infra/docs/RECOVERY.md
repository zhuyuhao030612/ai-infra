# 故障恢复手册

## 场景 1：local-agent 挂了

**症状**：`curl http://127.0.0.1:9000/health` 失败
**自动恢复**：watchdog 60s 内拉起
**手动**：
```powershell
cat D:\Code\local-agent\logs\watchdog.log | tail -5  # 看重启次数
# 如果 watchdog 也挂了：
pwsh -File D:\Code\local-agent\scripts\start.ps1
```

## 场景 2：GPT-5.5 管道不响应

**症状**：`gpt-ask.ps1` 返回 GPT_UNAVAILABLE
**诊断**：
```powershell
# 1. 进程在不在
Get-Process -Name "node"  # 有就说明在跑

# 2. 日志说什么
cat D:\Code\ai-pipeline\gpt55-output.log | tail -5
# [ready] = 在线
# [login] = 正在登录
# [error] = 出错了

# 3. 队列状态
ls D:\Code\ai-pipeline\gpt-queue\inbox\
ls D:\Code\ai-pipeline\gpt-queue\processing\
ls D:\Code\ai-pipeline\gpt-queue\failed\
```

**重启管道**：
```powershell
# 杀旧进程
Get-Process -Name "node" | Where-Object { $_.CommandLine -match "gpt55" } | Stop-Process -Force
# 清状态重来
rm D:\Code\ai-pipeline\state.json
# 启动
cd D:\Code\ai-pipeline && Start-Process node -ArgumentList "gpt55-server.js" -WindowStyle Minimized
```

## 场景 3：watchdog 无限重启风暴

**症状**：`watchdog.log` 频繁出现 RESTART
**暂停 watchdog**：关掉 Startup 快捷方式
**诊断根因**：`cat D:\Code\local-agent\logs\watchdog.log | Select-String "RESTART"`

## 场景 4：events.jsonl 过大

**症状**：`/status` 变慢
**处理**：
```powershell
# 查看大小
ls D:\Code\ai-infra\logs\events.jsonl
# 手动归档
mv D:\Code\ai-infra\logs\events.jsonl D:\Code\ai-infra\logs\events-archive.jsonl
```

## 场景 5：失败证据包太多

```powershell
pwsh -File D:\Code\ai-infra\scripts\cleanup-runs.ps1 -Days 14 -Apply
```

## 场景 6：Token 泄露

1. 修改 `D:\Code\local-agent\.env` 中的 token
2. 重启 local-agent
3. 更新所有引用 token 的地方

## 关键文件位置

| 文件 | 路径 |
|------|------|
| 审计日志 | `D:\Code\local-agent\logs\audit.jsonl` |
| Watchdog 日志 | `D:\Code\local-agent\logs\watchdog.log` |
| GPT 管道日志 | `D:\Code\ai-pipeline\gpt55-output.log` |
| 事件日志 | `D:\Code\ai-infra\logs\events.jsonl` |
| Token 配置 | `D:\Code\local-agent\.env` |
| GPT 缓存 | `D:\Code\ai-pipeline\gpt-cache\` |
| 失败证据包 | `D:\Code\ai-infra\failures\` |
