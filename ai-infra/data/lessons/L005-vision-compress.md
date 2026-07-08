---
tags: [vision, gui, screenshot, api, timeout]
match_keywords: [Vision超时, 大图压缩, JPEG质量40%, 裁剪窗口, 50KB以下, 豆包API, 2560x1440全屏失败]
date: 2026-06-28
source: ToDesk截图分析（2560x1440全屏→超时）
severity: medium
status: final
---

# Vision API 大图超时——必须先裁剪压缩

## Symptom
- 2560x1440全屏PNG（4MB）送Vision API → 超时无响应
- 即使裁剪到900x568 JPEG 41KB → 仍偶发超时
- 300x80 JPEG 2.5KB → 仍然超时（API本身不稳定）

## Trigger
- 全屏截图太大
- PNG未压缩
- API服务端不稳定

## Root Cause
豆包Vision API对图片大小敏感。需要裁剪到目标窗口区域并压成小JPEG。

## Fix
1. gui-probe.ps1 → 裁剪目标窗口→压缩JPEG质量40%
2. 目标大小：<50KB
3. 如仍超时：降级为像素扫描或人工确认

## Prevention
- 送Vision前检查文件大小：超过100KB必须再压缩
- Vision不可用 → 像素扫描/pyautogui定位/人工确认
- 不要依赖Vision作为唯一GUI定位手段
