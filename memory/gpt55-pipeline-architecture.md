---
name: gpt55-pipeline-architecture
description: GPT-5.5 v9 纯HTTP API+SSE流式——ai.nbai88.top中转站，浏览器仅维持cookies，支持/ask和/ask/stream双模式
metadata:
  type: reference
---

## GPT-5.5 管道 v6 — 直接 HTTP API

### 核心架构
**浏览器仅维持登录态（cookies），所有消息通过直接 HTTP API 收发，零 UI 操作。**

### 平台：ai.nbai88.top（ChatGPT 中转站）
- 无验证码/风控，只需账号密码登录
- **API 端点**：`POST /backend-api/f/conversation`（标准 ChatGPT 后端 API）
- **响应格式**：SSE（Server-Sent Events），需解析 `data:` 行
- **Model 参数**：`gpt-5-5-thinking`（默认）、`gpt-5`、`gpt-4o`、`auto`

### 服务端 (gpt55-server.js, :3000)
- **启动**：`node gpt55-server.js`（需 GPT_USER/GPT_PASS 环境变量）
- **首次启动**：Launch Playwright 浏览器 → 登录（自动点登录按钮+填凭据+选通道）→ 提取 cookies
- **后续启动**：从 `data/session-tokens.json` 加载 cookies，浏览器自动登录（persistent profile）
- **发送消息**：直接 HTTP POST `/backend-api/f/conversation`，解析 SSE 响应
- **上下文保留**：`conversation_id` 自动传递，同一对话窗口，越聊越快
- **Cookie 刷新**：每 30 分钟自动刷新；API 失败自动重试（刷新 cookies 后重发）
- **Headless 模式**：设 `GPT55_HEADLESS=1` 环境变量，浏览器不可见

### 关键设计决策
1. ❌ **不再模拟 UI 操作**（打字/点按钮/找选择器）—— 这些是之前卡死的根源
2. ✅ **直接 HTTP API** —— 速度 9-30s，零卡死风险
3. ✅ **浏览器仅管登录** —— cookies 过期才需要重新登录
4. ✅ **无超时限制** —— 等到 GPT 回复完成为止

### 端点
| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/ask` | 提交 prompt（body: `{prompt, model?}`），返回 `{id, state}` |
| GET | `/job/:id` | 轮询结果，`state=succeeded` 时含 `result` |
| GET | `/health` | `{hasCookies, conversationId, model, activeJobs}` |
| POST | `/new-chat` | 重置会话，下次开新对话 |
| POST | `/model` | 切换模型 `{model: "gpt-5"}` |
| POST | `/refresh` | 手动刷新 cookies |

### 客户端 (gpt-ask.ps1)
- 提交：`POST /ask` → 获取 job_id
- 轮询：`GET /job/:id` 每 3 秒
- 超时：默认 1800s

### 环境变量
- GPT_USER / GPT_PASS — 登录凭据
- GPT55_URL — 默认 https://ai.nbai88.top/
- GPT55_MODEL — 默认 gpt-5-5-thinking
- GPT55_HEADLESS — 设 1 隐藏浏览器
- PORT — 默认 3000

**Why:** Playwright UI 操作（打字/点击）是脆弱的根源。中转站暴露了标准 ChatGPT 后端 API，直接用 HTTP 调即可。
**How to apply:** 杀旧 server → 确保 GPT_USER/GPT_PASS 已设 → `node gpt55-server.js` → `pwsh -File gpt-ask.ps1 -Prompt "..."`。
