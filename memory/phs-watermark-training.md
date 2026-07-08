---
name: phs-watermark-training
description: PHS 水印分割模型训练经验——合成数据→真实帧微调路线
metadata:
  type: project
---

## WatermarkSeg 训练进化

### 教训
- 纯合成数据训练 IoU 再高（0.999）也泛化不到真图——背景纹理/字体/透明度都需要多样性
- 用项目自有视频抽帧做背景，合成水印叠加，再微调——泛化能力质变
- 全内存生成（OnTheFlyDataset）比文件 I/O 可靠，避免 make_watermark_bench.py 的 H.264/编码器 bug
- AMP + BCEWithLogits 不兼容 → 小模型直接用 FP32

### 模型版本
| 版本 | IoU | 泛化 | 数据 |
|------|-----|------|------|
| v1 | 0.966 | ❌ | 纯色/渐变/噪声 3000 合成 |
| v2 | 0.999 | ❌ | 6字体+旋转+半透明 8000 合成 |
| v3 | 0.989 | ✅ | v2 + 839真实帧微调 5000 |

### 关键文件
- `tools/train_watermark_seg_fast.py` — 主训练脚本（OnTheFlyDataset）
- `tools/finetune_seg.py` — 微调脚本（RealDataset, 从文件读）
- `tools/auto_process_video.py` — 自动抽帧→生成→训练
- `phs/engines/watermark/detectors/seg_detector.py` — 推理检测器
- `runtime/models/watermark_seg_v3.pt` — 当前最佳模型（14MB, 3.5M参数）

### 后续
- 真实直播录制放 `D:\PHS\samples\real_videos/` → 自动处理
- MiniUNet 的 base=24 偏小，可尝试 base=32 提升容量
- 需要用真实水印标注（非合成）做最终评估
