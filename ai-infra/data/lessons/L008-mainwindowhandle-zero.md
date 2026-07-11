---
tags: [windows, gui, process, enum-windows, automation]
match_keywords: [MainWindowHandle为0, Get-Process找不到窗口, 托盘应用, EnumWindows按PID枚举, Doubao无窗口, 后台进程GUI不可达]
date: 2026-06-28
source: P0-1 学习：Doubao/Notepad 对比测试
severity: high
status: final
---

# Get-Process MainWindowHandle 为 0 = 进程无顶层窗口

## Symptom
- `Get-Process` 能找到进程
- `MainWindowTitle` 为空字符串
- `MainWindowHandle` 为 0 (IntPtr.Zero)
- ShowWindow/SetForegroundWindow 无效

## Trigger
- 应用是纯托盘应用（系统通知区）
- 应用使用后台 helper 进程
- 窗口是 message-only window
- 所有窗口都是隐藏的子窗口

## Root Cause
`Get-Process` 的 `MainWindowHandle` 只返回进程的第一个可见顶层窗口句柄。如果进程所有窗口都被隐藏、最小化到托盘、或是 message-only 窗口，则返回 0。这不意味着进程没有窗口，只意味着没有"可见顶层窗口"。

## Fix
1. 先 `EnumWindows` + `GetWindowThreadProcessId` 按 PID 枚举所有窗口
2. 过滤可见且尺寸 > 100x100 的窗口
3. 如果没有 → 进程真的是无操作窗口，切 API/Web/其他方案
4. 如果有 → ShowWindowAsync + SetForegroundWindow

## Prevention
- GUI 自动化第一步：确认窗口存在（EnumWindows），不是确认进程存在
- Get-Process 只能确认"进程在跑"，不能确认"有窗口可操作"
