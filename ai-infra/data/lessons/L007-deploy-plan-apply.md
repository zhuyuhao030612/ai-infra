---
tags: [deploy, powershell, dry-run, idempotent]
match_keywords: [部署三阶段, Plan Apply Verify, dry-run模式, 不可逆操作保护, 部署脚本模板]
date: 2026-06-28
source: setup-v2.ps1多次在老板机器上报错
severity: high
status: final
---

# 部署脚本必须支持 -Plan/-Apply/-Verify 三阶段

## Symptom
- 部署脚本直接在老板机器上执行，报错后状态不可知
- 不知道哪些步骤已完成、哪些失败
- 重复执行可能重复添加防火墙规则、PATH条目

## Trigger
- 脚本没有dry-run模式
- 没有分阶段执行
- 一次运行包含多个不可逆操作

## Root Cause
部署脚本当作普通业务脚本写——直接执行所有步骤。但部署是状态变更，需要：先看要改什么、确认后执行、执行后验证。

## Fix
所有部署脚本使用三阶段模板：
```powershell
param([switch]$Plan, [switch]$Apply, [switch]$Verify)
```
- `-Plan`：只输出将执行的操作，不修改系统
- `-Apply`：真实执行
- `-Verify`：检查执行结果

## Prevention
- 新部署脚本必须支持三阶段
- ps-guard 检查是否缺少 Plan/Apply/Verify
- 老板机器上永远先 `-Plan`，确认后再 `-Apply`
