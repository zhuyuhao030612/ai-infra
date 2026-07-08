# 记忆索引

每条一行，内容在 `memory/` 目录下。向量记忆通过 mem0 MCP 自动加载。

## AI 基础设施
- [GPT-5.5 管道架构](memory/gpt55-pipeline-architecture.md) — ai.nbai88.top v9纯HTTP API+SSE流式,同窗口上下文,软错误不重启
- [Agent 委派失败模式](memory/agent-delegation-failure-pattern.md) — 反复承诺用Agent但全自己干，已确认为行为缺陷
- [主脑 API 不可切换](memory/do-not-switch-main-api.md) — DeepSeek V4 Pro 是唯一主脑，禁止替换
- [Nudge 引擎已实现](memory/hermes-nudge-implemented.md) — P0 Nudge 引擎，后台审查会话自动抽取记忆和技能
- [Skill 结晶系统](memory/skill-crystallization.md) — 5阶段自动结晶：追踪→评估→反思→结晶→存储
- [安全门禁已集成](memory/security-gatekeeper-integrated.md) — 14条威胁规则，写入前regex扫描，P0拦截
- [Skill库升级](memory/skill-library-v2.md) — 偷师4大开源项目，14个skill就位
- [Code 目录地图](memory/code-directory-map.md) — D:\Code 完整项目地图，2026-07-08审计后

## PHS / 棱镜 Prism Studio
- [PHS 架构状态](memory/phs-architecture-status.md) — 215文件,全链路E2E,前端v2消费级
- [Prism Studio 最终审计](memory/prism-studio-full-audit.md) — v1.5.0-RC2冻结,Doctor 28/28
- [PHS 项目治理](memory/phs-governance.md) — 锁定路线,模块唯一入口,防重复检查清单
- [PHS 关键教训](memory/phs-key-lessons.md) — 10条实战教训
- [PHS 水印训练](memory/phs-watermark-training.md) — WatermarkSeg v1→v6进化,IoU 0.993
- [PHS Mirage 裂变管线](memory/phs-mirage-pipeline.md) — 2h素材→168h不重复
- [PHS Mirage 审计清单](memory/phs-mirage-audit-checklist.md) — GPT-5.5代码审计标准
- [LTX-Insight Provider](memory/ltx-insight-provider.md) — 606行,LTX-2.3 DiT FP8,4 LoRA
- [Qwen3-TTS 选型](memory/qwen3-tts-selection.md) — SIM 0.95, 97ms延迟
- [Qwen3-TTS 克隆](memory/qwen3-tts-cloning.md) — 5s音频→8.5s合成

## 悬赏/PR
- [悬赏 PR 追踪](memory/bounty-pr-tracking.md)
- [悬赏平台发现](memory/claude-builders-bounty-discovery.md)
- [PR 审计与扩展](memory/pr-audit-and-extension.md)
- [PR 监控](memory/pr-monitoring.md)
- [PR #68 优化](memory/pr-68-optimization.md)
- [Claudio & Hermes 集成](memory/claudio-and-hermes-integration.md)

## 工具/工程
- [app 旧代码删除](memory/app-old-code-deletion.md)
- [obs_bridge 行修改](memory/obs_bridge-line-change.md)
- [Claude Code diff JSON 序列化](memory/claude-code-diff-json-serialization.md)
- [third-party junction 路径](memory/third-party-junction-path.md)
- [iPhone HEVC VFR→CFR](memory/iphone-hevc-vfr-to-cfr.md)
- [MPV display-resample 陷阱](memory/mpv-display-resample-pitfall.md)
- [Git Push 大文件](memory/git-push-large-files.md)
- [CosyVoice TTS 修复](memory/cosyvoice-tts-repair.md)
- [TypeScript 零错误](memory/typescript-error-free.md)
- [Steal Skills from Projects](memory/steal-skills-from-projects.md)
- [敏感Key去重](memory/sensitive-keys-duplicates.md)

## 记忆系统
- mem0 向量记忆：ChromaDB + Ollama nomic-embed-text
- MCP 已接入 `.mcp.json`，下次启动自动加载
- 原始 markdown 文件保留在 `memory/`，同步导入 mem0


- [preflight-skip-fix](memory/preflight-skip-fix.md) — This project involved addressing the issue of preflight skipping by implementing...