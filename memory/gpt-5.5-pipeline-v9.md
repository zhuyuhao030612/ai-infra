---
name: gpt-5.5-pipeline-v9
description: 重写了GPT-5.5管道v9，使用纯HTTP API直连中转站后端，并实现SSE流式输出。
metadata:
  type: project
---

Why: 通过移除Playwright UI操作和浏览器重启问题，提高了系统的稳定性和效率。
How-to-apply: 使用纯HTTP API与后端中转站通信，实现SSE流式输出。