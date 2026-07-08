---
name: phs-mirage-pipeline
description: PHS 24x7无人直播裂变管线架构——素材→变体→AB混合→音频裂变→随机调度
metadata:
  type: project
---

## PHS Mirage 裂变管线

### 目标
2小时原始素材 → 168小时不重复内容 → 24×7不间断直播

### 五阶段管线
1. **场景分割** — ffmpeg scene detect, 切30-90秒片段
2. **变体工厂** — ffmpeg批处理: 6裁剪×3调色×3速度×2镜像=108变体/片段
3. **AB帧混合** — `toki-plus/AB-Video-Deduplicator` 插入诱饵帧重构指纹
4. **音频裂变** — `python-audio-separator`(Demucs) 人声/BGM分离, 独立处理, 立体声延时差, 重混
5. **播放调度** — OBS WebSocket, 随机+不重复+间隔≥30min, 真人标记每60min

### 依赖
- AB-Video-Deduplicator: `github.com/toki-plus/AB-Video-Deduplicator`
- python-audio-separator: `github.com/nomadkaraoke/python-audio-separator`
- Demucs: `github.com/facebookresearch/demucs`
- Advanced Scene Switcher: OBS插件
- ffmpeg (系统自带)
- PHS现有: frame_randomizer, audio_environment, live_preprocessor

### 变体公式
N片段 × 6裁剪 × 3调色 × 3速度 × 2镜像 × 5AB混合 = N×540变体
2小时 ≈ 80片段 → 43,200变体 ≈ 远超168小时需求

### 关键路径
D:/PHS/prism/phs/mirage/ — 新模块目录

**Why:** 几小时素材循环24×7会被内容层面检测。裂变解决画面/音频/指纹三个维度的重复问题。
**How to apply:** 先调GPT-5.5写胶水代码，再对比源码审计优化。
