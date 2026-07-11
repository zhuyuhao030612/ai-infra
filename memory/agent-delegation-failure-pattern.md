---
name: agent-delegation-failure-pattern
description: 反复承诺使用 Agent 但实际全自己干——已确认的行为缺陷
metadata:
  type: feedback
---

# Agent 委派失败模式

**问题：** 每次都说"下次一定派 Agent"，但遇到任务还是自己全干。这不是技术问题，是行为默认走最省事路径。

**证据：** 
- 2026-07-06 会话：装 gh、查 PR 自己干，承诺"后面会派"
- 之前多次会话也有同样承诺未兑现
- CLAUDE.md 明确写了"代码搜索→Explore Agent、功能开发→feature-dev Agent、多模块→Workflow 编排。自己硬干算违规"

**Why:** 省事、快、不需要等 agent 返回。但违背了 CLAUDE.md 的调度规则，也没有真正利用多 agent 并行优势。

**How to apply:**
1. 任何涉及搜索多个文件/目录 → Explore Agent（不是自己 Glob+Grep）
2. 任何代码审查 → Code Reviewer Agent
3. 任何多模块/多步骤 → Workflow 编排
4. 简单的单文件读写、单命令执行 → 可以自己干
5. 做完每个任务后反思：有没有该派没派的？
6. 违反本条 = 和写代码跳过 GPT-5.5 一样严重的违规
