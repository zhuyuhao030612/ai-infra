---
name: phs-architecture-status
description: PHS→棱镜 Prism Studio 完整架构状态——215文件,全链路E2E通过,前端v2消费级 (2026-07-08 审计后更新)
metadata:
  type: project
---

## 棱镜 Prism Studio (原 PHS)

### 核心定位
素材进去，直播出来。手机真摄像头拍摄+声卡物理回路，OBS/虚拟驱动全砍。

**定位澄清**：直播自动化中控/半自动直播助手（非"无人直播挂机工具"）。OBS 虚拟摄像头输出→官方平台采集推流，PHS 不直接推流。

### 已接入链路
```
素材 → 去重(pHash+Chromaprint) → 水印检测(v6 IoU 0.993)
  → 修复(LaMa/ProPainter/AVID/LTX-Insight) → Mirage裂变
  → 帧随机化(9效果含灯光暗角) → Loop编译 → playlist.json
  → live_player全屏播放 → 4K屏 → 手机 → 抖音

弹幕 → collector_v2(自愈) → AI回复(Ollama 557ms)
  → 豆包TTS(seed-tts-2.0) → audio_mixer(BGM闪避20%)
  → 声卡Loopback → 音频线 → 手机
```

### 架构：四层
API(phs/server.py FastAPI :8080) → Orchestrator(流程编排/状态机/合规/回退) → Engine(material/audio/live/watermark) → Provider(18个统一注册)

### 模块归属（唯一入口原则）
- 百应业务域 `phs/baiying/`：弹幕→意图→审查→TTS→混音，**只有一条链**
- 素材引擎域 `app/material_engine/`：检测/清洁/变体/Loop/去重
- 音频底层域 `phs/audio/`：TTS合成/后处理/混音/指纹去重
- Runtime域 `app/live_runtime/`：Supervisor/GPU调度/容错
- Provider域 `phs/providers/`：18个已注册（ffmpeg/opencv/fpcalc/piper/obs/libvips等）
- **禁止新建第二条事件流**，所有TTS播报必经 `sensitive_guard.py`

### 已完成（截至 2026-07-04）
- SAM2 管线（权重857MB, 7/7验证）
- VQA 融合（VQAFusion+BatchProcessor）
- CosyVoice 替换 Piper（合成3.4s, CPU RTF 0.98，含Piper降级）
- VSC22 去重（VideoDedup+FrameDedup）
- 全链路 e2e 测试（tests/test_e2e_pipeline.py）
- 前端 v2 消费级重构（3页控制台：素材+开播+设置，OKLCH金箔暗色主题，SSE 实时推送，TypeScript 0错误）
- 7个P1产品模块（话术工作台/播后复盘/健康看板/素材资产库/评论运营/项目模板/多账号）
- 旧CLI入口废弃（migrate_cli.py，统一到 `python -m phs.cli run`）
- P0尾项全部完成：OBS断线自愈/跨轮次记忆10轮/30分钟黑屏检测/clean_rebuild升级
- 安装器 253MB（内嵌FFmpeg 434MB + libvips 45MB + Piper 60MB）
- Doctor v2: 28/28 PASS，Engine Reality: 11/11 PASS
- 水印模型：WatermarkSeg v6（IoU 0.993, 9695帧训练）
- LTX-Insight Provider：606行，LTX-2.3 DiT FP8 ~4.5GB，4个LoRA（水印/字幕/修复/超分）

### 模型权重
| 权重 | 路径 | 大小 |
|------|------|------|
| WatermarkSeg v6 | runtime/models/ | 14MB |
| SAM ViT-B | runtime/models/ | 358MB |
| SAM2 Large | runtime/models/sam2/ | 857MB |
| CosyVoice 2.0-0.5B | third_party/CosyVoice/ | 4.4GB |
| Cutie | third_party/Cutie/ | 134MB |
| COVER | third_party/COVER/ | 119MB |

### TTS 链路
豆包(seed-tts-2.0, 已接入) + 阿里/腾讯(待配Key) + Qwen3(降级, SIM 0.95, 97ms) + Piper(兜底)
Qwen3-TTS 克隆实测：5s音频→8.5s合成，x_vector_only_mode

### 硬件（待到位）
4K雾面屏 + Focusrite 4i4 + 偏振滤镜 + 音频线

### 待做
- 硬件到货后真机24h浸泡测试
- 阿里/腾讯TTS配Key
- 统一启动器
- RQ-VQA/ReLaX-VQA checkpoints（可选，暂缓）
- 移动端监控（暂缓）

### 关键路径
D:/PHS/prism/ — 主项目
D:/PHS/prism/STATUS.md — **唯一状态源**
D:/Code/Qwen3-TTS/ — Qwen3独立venv
D:/Code/GPT-SoVITS/ — GPT-SoVITS独立venv

### 禁止事项
- ❌ 不在 `app/` 新增代码（旧代码区）
- ❌ 不引用 `foundry_v04~v10` 旧CLI
- ❌ 不使用 `run_pipeline.py` 旧入口
- ❌ 不以 `PROGRESS.md` 或 `KNOWN_LIMITATIONS.md` 作为当前状态依据
- ❌ 不创建第二条事件流
- ❌ 不绕过 `sensitive_guard.py` 做TTS播报

**Why:** 全链路打通，等待硬件实测。215文件，全量E2E通过，前端消费级可用。
**How to apply:** 先读 `STATUS.md`→`ARCHITECTURE.md`→`ROADMAP.md`。素材→material_preprocessor→python live_player.py --playlist playlist.json
