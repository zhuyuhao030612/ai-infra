---
name: bounty-pr-tracking
description: 每次启动时检查 TentOfTrials bounty PR 是否 merge 赚钱了
metadata:
  type: project
---

启动后必须查 GitHub 上 zhuyuhao030612 在 cuentaprueba244w-dotcom/TentOfTrials 提交的所有 PR 状态，汇报哪些 merge 了（赚钱了）、哪些还开着。

**Why:** 老板每次想知道自己的悬赏 PR 赚没赚钱。

**How to apply:** `ai preflight` 之后，调 GitHub API 查 `author:zhuyuhao030612 repo:cuentaprueba244w-dotcom/TentOfTrials type:pr`，列出状态。
