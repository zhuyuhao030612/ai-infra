---
name: design-taste-frontend
description: Anti-slop frontend design skill. Gives AI design taste — stops it from generating boring, generic, templated UIs. Based on taste-skill (Leonxlnx) and Impeccable (pbakaus).
version: 1.0.0
source: taste-skill + Impeccable
---

# design-taste-frontend — 反 AI 模板脸

> 适用场景：AI 生成前端页面（landing page/portfolio/dashboard/管理后台）。
> 不是 UI 组件库，是一组设计约束规则。AI 生成代码前必须读取。

## 0. 先读上下文 (Design Read)

生成任何代码前，先推断：这是什么页面？给谁看？什么风格？

输出一行设计判断：
```
分析：<页面类型> for <受众>, <风格> 风格, 采用 <设计系统>
```

禁止默认审美：Inter 字体、紫色渐变、居中 hero、三列等大卡片、全屏玻璃效果、无限微动效。

## 1. 三个旋钮

| 旋钮 | 1 | 10 | 默认 |
|---|---|---|---|
| DESIGN_VARIANCE | 完美对称 | 艺术混沌 | 7 |
| MOTION_INTENSITY | 静态 | 电影级 | 5 |
| VISUAL_DENSITY | 画廊留白 | 驾驶舱 | 4 |

## 2. 色彩系统 — OKLCH (来自 Impeccable)

```css
/* 暗色主题 (PHS 直播中控) */
--bg-deep: oklch(4% 0.004 95);       /* 最深底 */
--bg-page: oklch(7% 0.006 95);       /* 页面底 */
--bg-raised: oklch(11% 0.006 95);    /* 面板/输入框 */
--bg-hover: oklch(15% 0.008 95);     /* 悬停态 */
--text-primary: oklch(91% 0 0);      /* 标题 */
--text-body: oklch(88% 0 0);         /* 正文 */
--text-muted: oklch(72% 0 0);        /* 辅助文字 */
--text-faint: oklch(62% 0 0);        /* 禁用文字 */
--accent: oklch(84% 0.19 80);        /* 主色 (金箔) */
--accent-hover: oklch(86% 0.07 84);  /* 悬停 */
--accent-active: oklch(77% 0.13 82); /* 按下 */
--danger: oklch(58% 0.15 35);        /* 危险 */
--success: oklch(45% 0.18 145);      /* 成功 */
--border: oklch(78% 0 0 / 0.16);     /* 分割线 */
--border-strong: oklch(74% 0.09 82 / 0.6); /* 强调分割线 */
```

## 3. 排版规则

- 标题用 `font-weight: 600`（不用 700 Bold）
- 正文 `line-height: 1.6`，小字 `1.5`
- 字号阶梯：12/14/16/20/28/40/56px
- 不用 Inter（AI 默认指纹）→ 用系统字体栈或 Geist/Satoshi
- 代码块用等宽字体，背景 `--bg-deep`，圆角 8px

## 4. 布局规则

- 禁止三列等大卡片布局（AI 模板脸 #1）
- 禁止居中 hero + 深色网格背景（AI 模板脸 #2）
- 用不对称网格：2/3 + 1/3, hero左对齐, 卡片高度不一致
- 间距用 4/8/12/16/24/32/48/64px 阶梯
- 最大内容宽度 1280px，侧边栏 260px

## 5. 动效规则

- 禁止弹跳缓动（bounce/elastic）
- 用 `cubic-bezier(0.16, 1, 0.3, 1)`（ease-out-expo）
- 微交互 < 200ms，页面切换 < 400ms
- 禁止 `infinite` 循环动画（除非加载指示器）
- 滚动触发用 `scroll-driven animation` 或 Intersection Observer

## 6. 反模式黑名单 (来自 Impeccable 44条检测)

生成代码后自检：
- ❌ 纯黑 `#000` 或纯白 `#fff` → 用 tinted token
- ❌ 灰色文字在彩色背景上
- ❌ Inter + slate-900 组合
- ❌ 紫色渐变 hero
- ❌ 卡片套卡片
- ❌ 弹跳/弹性缓动曲线
- ❌ `<div>` 做按钮 → 用 `<button>`
- ❌ 缺少 `:focus-visible` 样式
- ❌ 小于 14px 的文字
- ❌ 低对比度文字（< 4.5:1）

## 7. 预检清单

生成代码后逐项检查：
1. [ ] 色彩用的 OKLCH 而非 hex/rgb
2. [ ] 无 AI 模板脸元素（见 §6）
3. [ ] 动效用 ease-out-expo 而非 bounce
4. [ ] 侧边栏导航清晰
5. [ ] 间距阶梯一致
6. [ ] 深色主题下对比度达标
