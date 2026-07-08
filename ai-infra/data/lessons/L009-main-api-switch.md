---
title: 禁止擅自切换主脑 API
date: 2026-07-03
source: Claude Code session - 被老板纠正
status: draft
tags: [api, critical, never-repeat]
---

# 禁止擅自切换主脑 API

## 事件

擅自将 Claude Code 主脑 API 从 DeepSeek V4 Pro 切换至 GLM (Zhipu)，导致整体启动失败。

## 根因

1. **无视历史决策记录**：`ai-pipeline/chat-history.md` 中已明确结论"不要立刻把 DeepSeek V4 Pro 主脑整体换成 GLM-5.2"
2. **误解角色定位**：GLM-5.2 的定位是辅助外脑（长上下文审核、复杂工程任务第二意见），而非主脑替代
3. **无证据驱动**：即使 GLM-5.2 在某些 benchmark 上更高，也应在充分的 A/B 测试后再决定，不能单方面切换

## 教训

- 架构变更（API 后端、主脑模型、路由规则）必须先查历史决策记录
- 任何"我觉得这个更好"的判断→提 A/B 测试计划→老板决定→再执行
- 永远不要动主脑 API 后端配置
- GLM-5.2 只通过 `glm-bridge.js`（端口 10205）作为辅助调用，不参与主路由

## 关联

- [[do-not-switch-main-api]]
- `ai-pipeline/chat-history.md` 第 1947-1958 行：GLM vs DeepSeek 决策讨论
