---
name: phs-governance
description: PHS项目治理规则——锁定版路线、模块归属、防重复开发、发布标准 (2026-07-08 从项目文档提取)
metadata:
  type: reference
---

## PHS 项目治理规则

> 来源：`D:/PHS/prism/docs/ROADMAP.md` + `MODULE_OWNERSHIP.md` + `DO_NOT_DUPLICATE.md` + `RELEASE_CRITERIA.md`

### 六条设计原则（锁定）
1. **正常直播画面优先** — 默认无字幕/商品卡/评论浮层/强制数字人
2. **AI 语音是互动核心** — 评论→意图→商品匹配→风险过滤→TTS播报，不贴画面
3. **数字人只桥接不自研** — DigitalHumanProvider接口，失败降级到素材+TTS
4. **高难度底层能力全部 Provider 化** — 不自研大模型
5. **PHS 免费，外部工具用户自选** — 不绑定任何付费服务
6. **为不擅长表达的人降低直播门槛** — 支持不露脸、不口播、低压力直播

### 版本路线（锁定，2026-06-28）
| 版本 | 目标 | 状态 |
|------|------|------|
| v1.1.1 交付硬化 | 非开发者能装能跑能演示 | ✅ |
| v1.2.0 画面质量商业化 | 变体85%+，300素材，2h长稳 | ✅ |
| v1.3.0 AI语音互动 | 商品知识库+评论+意图+TTS | ✅ |
| v1.4.0 Provider+数字人 | Provider矩阵+DH接口 | ✅ |
| v1.5.0 本地Studio | 多项目/多素材/审计日志 | ✅ RC2 |
| v2.0 云端企业扩展 | 触发条件：3-5真实案例+付费场景 | 待触发 |

### 全局不做
- 不默认字幕/商品卡/评论浮层/数字人/贴纸特效上屏
- 不自研数字人/TTS大模型/RTC/虚拟摄像头驱动
- 不绑定付费工具作为主链路
- 不做违规评论抓取和绕过平台限制
- 不在 v1.x 做云 SaaS
- 不承诺收益

### 模块唯一入口（关键）
| 能力 | 唯一入口 | 禁止新建 |
|------|---------|---------|
| 弹幕采集 | `phs/baiying/bridge.py` | ❌ |
| 敏感词审查 | `phs/baiying/sensitive_guard.py` | ❌ **所有播报必经** |
| 话术模板 | `phs/baiying/script_manager.py` | ❌ |
| TTS任务队列 | `phs/baiying/tts_queue.py` | ❌ |
| 直播音频混音 | `phs/baiying/audio_mixer.py` | ❌ |
| 商品知识库 | `live_commerce.py::ProductKnowledgeBase` | ❌ |
| 全局Supervisor | `app/live_runtime/live_engine.py` | ✅ 只做启停/守护 |

### 统一事件流（只有一条链）
```
百应页面 → bridge.py(弹幕) → product_collector.py(商品)
  → live_commerce.py(意图) → script_manager.py(话术)
  → sensitive_guard.py(审查) ← 所有播报必经
  → tts_queue.py(排队) → voice_engine.py(合成)
  → audio_dedup.py(去重) → audio_mixer.py(混音)
  → VB-Cable/AV合流 → 直播输出
```

### 新建模块前检查清单
```
□ 已 Grep 全仓库是否有类似模块？
□ 已查 MODULE_OWNERSHIP.md 是否已有唯一入口？
□ 这个模块属于哪个域？（百应/素材/音频/AV/Runtime/Provider/Web）
□ 会不会创建第二套事件流？
□ 如果已有入口，是否应作为"底层能力"接入而非新建？
```

### 已发生的重复（已修复，警示）
| 时间 | 新建 | 已有 | 处理 |
|------|------|------|------|
| 07-03 | voice_engine.py | tts_queue.py | voice_engine降为底层引擎 |
| 07-03 | natural_mixer.py | audio_mixer.py | 策略并入audio_mixer |
| 07-03 | script_generator.py | script_manager.py | 降为辅助工具 |
| 07-03 | live_engine.py | bridge.py | 降为Supervisor |

### 发布标准
- 每个版本必须有 Release Notes + Known Limitations + Doctor/Report
- 不能破坏主入口和默认正常直播画面
- 不符合当前版本目标的任务进 backlog，不插队
- 先验收当前版本，再进入下一版本

**Why:** 防止玄策式重复开发踩坑。PHS 百应链只有一条，所有模块唯一入口。
**How to apply:** 新建任何模块前 Grep 关键词→查 MODULE_OWNERSHIP.md→确认域归属→确认不创建第二条事件流。
