---
tags: [powershell, deployment, strictmode, setup]
match_keywords: [StrictMode, switch参数冲突, 变量未设置, VariableIsUndefined, 部署脚本语法, Set-StrictMode]
date: 2026-06-28
source: setup-v2.ps1部署WiFi Win10失败
severity: medium
status: final
---

# PowerShell StrictMode 与 switch 参数冲突

## Symptom
```
检索不到变量"$DryRun"，因为未设置该变量。
所在位置 setup-v2.ps1:4 字符: 15
+ param([switch]$DryRun)
```
脚本第一行就报错，`Set-StrictMode -Version Latest` 把未传入的 switch 参数当作未定义变量。

## Trigger
- PowerShell脚本使用 `Set-StrictMode -Version Latest`
- 参数中有 `[switch]` 类型
- 调用时未传入该 switch

## Root Cause
`StrictMode Latest` 要求所有变量必须先定义再使用。`[switch]$DryRun` 在未传入时默认应为 `$false`，但 StrictMode 在 `param()` 块执行前就检查了变量。

## Fix
部署脚本中移除 `Set-StrictMode`，或在 `param()` 块之前不允许出现任何代码。对于需要严格模式的脚本，将 param 放在最顶部。

## Prevention
- 部署脚本不需要 StrictMode（灵活性优先）
- 逻辑脚本可以用 StrictMode（正确性优先）
- ps-guard 应检测 StrictMode + switch 组合并警告
