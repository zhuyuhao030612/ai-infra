# D:\Code 项目地图

> 最后更新：2026-07-08

## 核心

| 目录 | 用途 |
|------|------|
| `ai-infra/` | AI 运行时中枢——ai.ps1、注册表、hooks、自学习 |
| `ai-pipeline/` | GPT-5.5 管道 v9——纯 HTTP API + SSE 流式 |
| `local-agent/` | Windows 系统代理 FastAPI :9000 |
| `.claude/` | Claude Code 配置——7 agents、3 hooks、settings |

## MCP

| 目录 | 用途 |
|------|------|
| `windows-computer-use-mcp/` | Windows CUA MCP Server |
| `.playwright-mcp/` | Playwright 浏览器 MCP |
| `mem0-server/` | 向量记忆 MCP——ChromaDB + Ollama |

## 记忆

| 目录 | 用途 |
|------|------|
| `memory/` | 29 个 markdown 记忆文件 |
| `MEMORY.md` | 记忆索引 |

## 项目

| 目录 | 用途 |
|------|------|
| `TentOfTrials-bounty/` | 悬赏 PR 项目 |
| `data/` | PHS 业务数据 |

## 系统

| 目录 | 大小 | 说明 |
|------|------|------|
| `.cache/` | ~22G | pip/huggingface/ollama 缓存 |
| `AppData/` | ~4G | QQ浏览器+WPS+直播伴侣 |
| `worktrees/` | — | Git worktrees |

## 根文件

| 文件 | 用途 |
|------|------|
| `CLAUDE.md` | AI 行为指令 |
| `MEMORY.md` | 记忆索引 |
| `CREDENTIALS.md` | 凭据（禁止外发） |
| `PROJECT_MAP.md` | 本文件 |
| `health.ps1` | 健康检查 |
| `send-to-claude.ps1` | GUI 发送 |
| `upgrade-claude.ps1` | 升级 Claude |
