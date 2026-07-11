# 模型交接协议

任何 AI 模型接管本系统时，按此文档操作。

## 1. 系统入口

```powershell
pwsh -File D:\Code\ai-infra\scripts\ai-start.ps1 -Task "任务描述"
```
自动分类任务类型，输出必须步骤。**不要跳过这一步。**

## 2. 关键文件

| 文件 | 作用 |
|------|------|
| `CLAUDE.md` | 行为规范 + 护栏规则 |
| `PROJECT_MAP.md` | 项目结构和依赖 |
| `TOOLS.json` | 所有工具注册表 |
| `.ai-state/state.json` | 唯一状态源 |
| `PLAYBOOKS.md` | 部署/GUI/阻塞标准流程 |

## 3. 强制规则

- PowerShell 交付前 → ps-guard
- 部署前 → env-probe  
- GUI 前 → gui-probe → 裁剪截图 → Vision
- 失败两次 → blocker-pack + 问外脑
- 没有反馈信号 → 不许连续动作

## 4. 状态检查

```powershell
curl http://127.0.0.1:9000/status          # 公开版
curl http://127.0.0.1:9000/status/full     # 完整版(需token)
pwsh -File D:\Code\ai-infra\scripts\ai-doctor.ps1   # 一屏诊断
```

## 5. 外脑

```powershell
# 管道已运行 → 直接发队列
pwsh -File D:\Code\ai-infra\scripts\gpt-ask.ps1 -Prompt "问题" -TimeoutSec 120

# 管道未运行 → 启动
node D:\Code\ai-pipeline\gpt55-server.js
```

## 6. 本地API

所有端点: `http://127.0.0.1:9000`
Token: 见 TOOLS.json 或 .env
