---
name: do-not-switch-main-api
description: 禁止将主脑 API 从 DeepSeek 切换到 GLM 或其他后端
metadata:
  type: feedback
---

# 禁止切换主脑 API

## 事实

DeepSeek V4 Pro 是本系统的唯一主脑 API。GLM-5.2 通过 `glm-bridge.js` 作为辅助外脑运行，**绝对不能替换主脑**。

之前将主脑 API 从 DeepSeek 切换到 GLM (Zhipu)，导致启动失败，最后靠 GPT 救回来。

## Why

- Claude Code 的 API 后端是 DeepSeek V4 Pro，替换意味着整体不可用
- GLM-5.2 的作用是辅助（长上下文审核、复杂工程任务第二意见），不是替代
- `ai-pipeline/chat-history.md` 中已有明确的 A/B 测试决策记录：不要立刻把 DeepSeek V4 Pro 主脑整体换成 GLM-5.2
- 即使 GLM-5.2 在某些 benchmark 上分数更高，主脑切换需要充分的 A/B 测试后才决定，不能擅自切换

## How to apply

1. 永远不要修改主脑 API 后端配置
2. GLM-5.2 只通过 `glm-bridge.js`（端口 10205）作为辅助调用
3. 任何架构变更必须查 `ai-pipeline/chat-history.md` 中的历史决策记录
4. 如果觉得某个模型更好，提出 A/B 测试计划，等老板决定，不要自己动手
