---
tags: [gui, todesk, UIA, SendKeys, vision, automation]
match_keywords: [ToDesk盲操, 自绘UI, UIA失败, SendKeys打到错误窗口, GUI无反馈, 远程桌面自动化, 窗口激活失败, Alt+Tab盲切]
date: 2026-06-28
source: ToDesk连接Win10尝试（10+次失败）
severity: high
status: final
---

# ToDesk 自绘UI无标准控件 UIA读不到 SendKeys盲打不可靠

## Symptom
- UIA FindAll返回0个Edit/Button控件
- SendKeys输入打到浏览器而非ToDesk
- Alt+Tab无法可靠切换到目标窗口
- 窗口标题从"ToDesk"变成远程计算机名

## Trigger
- ToDesk使用自绘UI框架（非标准Win32控件）
- 远程连接建立后窗口标题动态变化
- 输入焦点在不可预测的窗口中

## Root Cause
自绘UI不暴露UIA控件树。SendKeys打到前台窗口，而前台窗口可能不是目标。没有反馈闭环，每步操作无法验证。

## Fix
1. gui-probe.ps1 激活+裁剪截图+UIA dump
2. Vision分析裁剪图定位控件相对坐标
3. 窗口矩形换算绝对坐标后点击
4. 截图hash对比验证状态变化
5. 失败两次 → 切SSH/RDP/人工

## Prevention
- GUI操作前必须 gui-probe
- 没有截图hash验证不许连续动作
- 同方案失败2次 → blocker-pack + 换路
- 优先SSH/RDP，GUI作为最后手段
