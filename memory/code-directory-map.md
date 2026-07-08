---
name: code-directory-map
description: D:\Code 完整目录地图——2026-07-08 审计清理后，22目录11根文件
metadata:
  type: reference
---

## D:\Code 目录地图（2026-07-08 审计后）

### 核心基础设施
| 目录 | 用途 |
|------|------|
| `ai-infra/` | AI 运行时——ai.ps1 入口、注册表、hooks、skills、自学习闭环 |
| `ai-pipeline/` | GPT-5.5 管道 v9——gpt55-server.js 纯HTTP API + SSE流式 |
| `agent-hub/` | 多模型适配器中心 |
| `agency-agents/` | Agent 定义 |
| `local-agent/` | Windows 系统代理 |

### GPT-5.5 管道
- `ai-pipeline/gpt55-server.js` — v9，直接 HTTP API 调中转站后端
- `ai-pipeline/data/` — profile/queue/session-tokens
- `ai-pipeline/gpt-cache/` — gpt-ask.ps1 响应缓存
- `ai-pipeline/start-gpt55.bat` / `start-gpt55-visible.bat`
- `ai-pipeline/specs/` — PHS frame-randomizer + mirage spec
- `ai-pipeline/templates/` — review-packet 模板
- `ai-pipeline/scripts/verify.ps1`

### PHS / 棱镜
- 主项目：`D:/PHS/prism/`
- 记忆：见 MEMORY.md PHS section

### 项目
| 目录 | 用途 |
|------|------|
| `TentOfTrials-bounty/` | 悬赏 PR |
| `impeccable/` | 开源参考 |
| `taste-skill/` | Taste Skill |
| `posters/` | 海报 |
| `patches/` | 补丁 |

### MCP
| 目录 | 用途 |
|------|------|
| `windows-computer-use-mcp/` | Windows CUA MCP |
| `.playwright-mcp/` | Playwright MCP |

### 配置/数据
| 路径 | 用途 |
|------|------|
| `CLAUDE.md` | 项目指令 |
| `MEMORY.md` | 记忆索引 |
| `PROJECT_MAP.md` | 项目地图 |
| `CREDENTIALS.md` | ⚠️ 凭据（保留，不可外发） |
| `memory/` | 记忆存储 |
| `data/` | PHS 业务数据 |
| `worktrees/` | Git worktrees |

### 系统缓存（不删）
| 目录 | 大小 | 内容 |
|------|------|------|
| `.cache/` | ~22G | pip/HF/ollama/playwright/npm/uv 缓存 |
| `AppData/` | ~4G | QQ浏览器+WPS+直播伴侣 |

### 已清理（2026-07-08）
- GPT-SoVITS (3.8G)
- Docker Desktop + 数据 (36G)
- GLM bridge/files
- 旧截图/日志/测试脚本/维护脚本
- 7个空目录

**Why:** 2026-07-08 全面审计，D:\Code 从 85GB 降到 ~40GB，31目录→22目录。
**How to apply:** 找项目查此表，不确定用途不要删。
