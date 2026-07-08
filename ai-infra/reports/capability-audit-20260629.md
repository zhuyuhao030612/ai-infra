# 注册表能力对齐审计 — 2026-06-29

## 运行态快照

| 服务 | 端口 | 状态 |
|------|------|------|
| Ollama (qwen2.5-coder:7b) | 11434 | ✅ 在线 |
| GPT-5.5 Pipeline | 文件队列 | ✅ 在线 |
| local-agent | 9000 | ❌ 挂了 |
| Agent Hub | 9100 | ❌ 挂了 |

## 逐模块审计

### 0. 启动协议 ✅ 正常
- CAPABILITY_REGISTRY.md 存在
- agent-self-check.ps1 可用
- Hook 链完整：PreToolUse→PostToolUse→Stop

### 1. 代码/测试/重构 ⚠️ 部分缺
| 注册表项 | 状态 | 说明 |
|----------|------|------|
| Grep+Read+Edit | ✅ | 内置工具 |
| ps-guard | ✅ | 脚本存在 |
| evidence-check | ✅ | 脚本存在 |
| multi-file-change Skill | ❌ 占位 | 技能目录无此Skill |
| GLM-5.2 (glm-ask) | ⚠️ | 脚本存在但Agent Hub挂了，无法通过agent-ask调用 |
| GPT-5.5 (gpt-ask) | ✅ | 管道在线 |
| security-review Skill | ✅ | 内置Skill |

### 2. 文件/搜索/批量 ✅ 正常
- Glob/Grep/Read/Edit/Write 全部内置
- ps-guard 可用
- security-gate ⚠️：注册表引用但 hooks 目录无此脚本，靠 block-dangerous.ps1 兜底

### 3. 浏览器/网页 ⚠️ 已配置未连接
| 注册表项 | 状态 | 说明 |
|----------|------|------|
| Playwright MCP (全系) | ⚠️ | 权限已开(mcp__playwright__**)，MCP server已配置，但工具未出现在当前会话→可能未连接 |
| **兜底可用** | | WebSearch + WebFetch + PowerShell |
| WebFetch → 外部域名 | ⚠️ | 多数域名被安全策略拦，需立刻切PowerShell |

### 4. Windows桌面/GUI ⚠️ 已配置未连接
| 注册表项 | 状态 | 说明 |
|----------|------|------|
| Windows Computer Use MCP | ⚠️ | 已安装(D:\Code\windows-computer-use-mcp)，settings.local.json已配置mcpServer，工具未出现→需排查连接 |
| computer-control-mcp | ⚠️ | 已配置，同上 |
| local-agent :9000 | ❌ 挂了 | 本可做桌面REST兜底 |
| **兜底可用** | | screenshot-vision.ps1 + PowerShell |

### 5. 记忆/改错本 ⚠️ 部分可用
| 注册表项 | 状态 | 说明 |
|----------|------|------|
| mem0_cli.py search | ⚠️ | yaml模块缺失，需修复 |
| MEMORY.md | ✅ | 可用 |
| mistake-log.md | ✅ | 可用 |
| memory-search.ps1 | ✅ | 脚本存在 |
| lessons-search.ps1 | ✅ | 脚本存在 |
| memory-add.ps1 | ✅ | 脚本存在 |

### 6. 学习/研究 ✅ 正常
- self-learn Skill → WebSearch→Ollama→GPT-5.5→存档 ✅
- deep-research Skill ✅
- WebSearch/WebFetch ✅

### 7. AI模型/Agent Hub ⚠️ 核心缺口
| 注册表项 | 状态 | 说明 |
|----------|------|------|
| Agent Hub :9100 (agent-ask) | ❌ 挂了 | 多模型统一网关不可用 |
| DeepSeek V4 Pro (主脑) | ✅ | 当前会话 |
| Ollama qwen2.5-coder | ✅ | 直接调API可用 |
| GPT-5.5 (gpt-ask.ps1) | ✅ | 文件队列可用 |
| 豆包 Vision (vision.js) | ✅ | API直接可用 |
| GLM-5.2 | ⚠️ | glm-ask.ps1存在但未验证 |

### 8. 安全/权限/外发 ✅ 正常
| 注册表项 | 状态 | 说明 |
|----------|------|------|
| block-dangerous.ps1 | ✅ | PreToolUse Hook (.claude\hooks) |
| pretool-guard.ps1 | ✅ | PreToolUse Hook (ai-infra\hooks) — matches PowerShell\|Bash |
| posttool-recorder.ps1 | ✅ | PostToolUse Hook (.claude\hooks) |
| post-tool-recorder.ps1 | ✅ | PostToolUse Hook (ai-infra\scripts) — global matcher |
| task-stop.ps1 | ✅ | Stop Hook (ai-infra\hooks) |
| task-ledger.ps1 | ✅ | Stop Hook (ai-infra\scripts) |
| stop-gate.ps1 | ✅ | 实际通过 task-stop.ps1 执行 |
| redact.ps1 | ✅ | 脚本存在

### 9. 运维/健康 ✅ 正常
- health-check.ps1 ✅
- ai-doctor.ps1 ✅
- gpt55-ctl.ps1 ✅

### 10. 任务/证据/收尾 ✅ 正常
- TaskCreate/Update/List 内置
- evidence-check.ps1 ✅
- close-run.ps1 ✅
- finish-task Skill ✅
- new-run.ps1 ✅

### 11. 媒体/图片/视频 ⚠️ 部分
- screenshot-vision.ps1 + vision.js ✅
- media-toolkit.ps1 ✅
- OCR ❌ 无直接工具，需豆包兜底

### 12. 远程/ToDesk ✅ 脚本存在
- todesk-connect.ps1 / activate-todesk.ps1 ✅

### 13. 内置工具 ✅ 全部可用
Agent / Bash / PowerShell / PlanMode / Worktree / Cron / Monitor / Skill / Workflow / DesignSync / NotebookEdit

### 14. Skill ✅ 内置齐全
finish-task / self-learn / gpt55 / deep-research / frontend-design / code-review / security-review / simplify / verify / loop / run / init

### 15. Hook ⚠️ 3/5在线
| Hook | 状态 |
|------|------|
| block-dangerous | ✅ |
| posttool-recorder | ✅ |
| stop-gate | ✅ |
| lint-python | ✅ |
| lint-typescript | ✅ |
| pretool-guard | ❌ 脚本不存在 |

### 16. 本地服务 ⚠️ 2/4在线
| 服务 | 状态 |
|------|------|
| Ollama :11434 | ✅ |
| GPT-5.5 文件队列 | ✅ |
| local-agent :9000 | ❌ |
| Agent Hub :9100 | ❌ |

### 17. 默认决策表 ⚠️ 需修正

| 场景 | 注册表写 | 实际应改 |
|------|----------|----------|
| 浏览器操作 | Playwright MCP | WebSearch/WebFetch + PowerShell |
| 桌面GUI | Windows Computer Use MCP | PowerShell + screenshot-vision |
| 多模型调用 | Agent Hub agent-ask | 直接调各API/脚本 |

### 18. 禁止行为 ✅ 仍然有效

---

## 最终状态（审计修正后）

| 服务/MCP | 端口 | 状态 |
|------|------|------|
| Ollama (qwen2.5-coder:7b) | 11434 | ✅ 在线 |
| GPT-5.5 Pipeline | 文件队列 | ✅ 在线 |
| Playwright MCP | npx自动发现 | ✅ 已连接 |
| Windows Computer Use MCP | stdio(uv) | ⏸ 等待审批(重启Claude Code时批准) |
| local-agent | 9000 | ❌ 挂了 |
| Agent Hub | 9100 | ❌ 挂了 |

## 本次修复

1. ✅ Playwright MCP — 确认已连接，`claude mcp list` 显示 Connected
2. ✅ Windows MCP — 通过 `claude mcp add` 注册到 `.mcp.json`，等重启审批
3. ✅ pretool-guard.ps1 — 确认存在于 `ai-infra\hooks\`，已在 settings.local.json 配置为 PreToolUse Hook
4. ✅ Hook 链路 — 确认 5 个 Hook 全部配置且脚本存在
