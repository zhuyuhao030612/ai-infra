# LTX-Insight Provider 集成记录

## 创建文件
- `D:/PHS/Prism Studio/providers/video_inpaint/ltx_insight_provider.py` (606行)

## 模型信息
- 基座: Lightricks/LTX-2.3 DiT, FP8 checkpoint (~4.5GB)
- LoRA 适配器 (4个): watermark_rm, subtitle_rm, restoration, hd_upscale
- 推理入口: `run_pipeline.py` CLI (subprocess 调用)
- HF: joyfox/LTX2.3-ICEdit-Insight (Apache 2.0)
- Paper: LTX-Insight: Unified Video Restoration and Semantic Editing (May 2026)

## Provider 能力
- `remove_watermark()` — 短视频水印/logo 移除
- `remove_subtitles()` — 硬字幕/弹幕移除
- `restore_video()` — 压缩伪影/降噪修复
- `list_available_loras()` — 列出已下载 LoRA 状态
- `get_model_info()` — 完整状态报告
- `download_model()` — 返回下载命令（不自动下载）

## 接口遵循
- PHS Provider protocol (`id`, `name`, `capabilities`, `probe()`, `configure()`)
- `probe()` 返回 `ProviderHealth`，status = "ready"|"missing"|"degraded"
- 模型未下载时优雅降级，不崩溃

## GPU 要求
- 最低 8GB VRAM，FP8 模式下可降至 ~6GB
- 当前环境: 15.9GB 空闲
