---
name: prism-studio-full-audit
description: 棱镜 Prism Studio 最终审计——代码、模型、链路、版本状态 (2026-07-08 对齐STATUS.md)
metadata:
  type: project
---

## 棱镜 Prism Studio 最终状态

### 版本：v1.5.0-RC2（BOSS ACCEPTED 2026-06-28，冻结 2026-06-29）

### 代码：215文件，全链路E2E通过

**直播闭环 (8文件)** ✅
- live_player.py: OpenCV全屏播放Mirage playlist + TTS混音
- collector_v2.py: 生产级弹幕采集（崩溃自愈+6选择器链+检查点）
- reply_engine.py: AI回复（Ollama 557ms）
- tts_router.py: 豆包TTS(seed-tts-2.0) + 阿里/腾讯/Qwen3/Piper四级降级
- baiying/audio_mixer.py: BGM闪避(20%)+TTS叠加
- engines/frame_randomizer.py: 9效果去指纹（含动态灯光+暗角）
- engines/audio_environment.py + audio_enhancer.py

**素材管线 (8文件)** ✅
- material_preprocessor.py: 水印(模型v6+OpenCV) + 修复(LaMa/ProPainter/AVID)
- mirage/ (6): 分割→108变体→AB混合(240fps)→Demucs音频→调度

**百应互动链** ✅
- bridge.py → product_collector.py → live_commerce.py → script_manager.py → sensitive_guard.py → tts_queue.py → voice_engine.py → audio_dedup.py → audio_mixer.py

**核心引擎 (70文件)**: material_engine全流程 ✅
**前端 v2**: 3页控制台(素材+开播+设置)，OKLCH金箔暗色主题，SSE实时推送，TypeScript 0错误 ✅

### 模型
- 内置: WatermarkSeg v6 (14MB, IoU 0.993) + Piper 60MB + SAM ViT-B 358MB
- 外部: SAM2 857MB + CosyVoice 4.4GB + Cutie 134MB + COVER 119MB
- 第三方: Qwen3-TTS 0.6B + GPT-SoVITS v2
- Provider: LTX-Insight (LTX-2.3 DiT FP8 ~4.5GB, 4 LoRA)

### TTS: 豆包(已接入) + 阿里/腾讯(待配Key) + Qwen3(降级, SIM 0.95) + Piper(兜底)

### 验证状态
- Doctor v2: 28/28 PASS（GPU+CUDA+二进制+JSON）
- Engine Reality: 11/11 运行时验证 PASS
- Smoke: PASS 2.7s
- Regression: 5/5 PASS
- OBS WebSocket 5.7.3 正常
- 安装器 253MB 干净安装通过
- 30分钟长直播：859MB/80秒生成
- 跨轮次记忆：10/10验证通过

### 硬件（待到位）
4K雾面屏 + Focusrite 4i4 + 偏振滤镜 + 音频线

### 待做
- 硬件到货后真机24h浸泡测试
- 阿里/腾讯TTS配Key
- 统一启动器
- 封闭验证（3-5用户试用）

### 完整链路
```
素材→去重(pHash+Chromaprint)→水印(v6)→修复(LaMa/ProPainter/AVID/LTX-Insight)
  →Mirage(AB混合+裂变)→帧随机化(9效果)→playlist→4K屏→手机→抖音
弹幕→AI→豆包TTS→audio_mixer闪避→声卡→手机
```

**Why:** 素材进去直播出来，弹幕AI自动回复，画面音频双重防检测。RC2已冻结，等待硬件实测。
**How to apply:** 素材 → material_preprocessor → python live_player.py --playlist playlist.json
