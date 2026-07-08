# Spec: PHS 帧随机化引擎 + 音频环境模拟

## 背景
PHS (Prism Hope Studio) 是直播带货素材智能中控。核心链路：素材导入→水印检测→修复→Loop编译→TTS→OBS输出。
现在需要防平台帧指纹检测——对视频做实时随机化处理，对音频做环境模拟，让录播看起来像实拍。

## 已有基础设施
- Python 3.12, OpenCV, numpy, librosa, soundfile
- 项目路径: `D:\PHS\prism\phs\`
- AugLy (facebookresearch/AugLy) 已 clone 到 `D:\Code\AugLy\`
- real-time-video-effects 已 clone 到 `D:\Code\real-time-video-effects\`
- CosyVoice TTS 已就绪 (4.4GB)
- PHS 已有 `phs/engines/` 目录结构

## 模块 1: 帧随机化引擎

### 输入
- 视频文件路径 (mp4/mov/avi)
- 可选：输出路径（不传则覆盖）

### 处理（每个参数独立可配置，带随机范围）

| 效果 | 参数 | 实现方式 |
|------|------|---------|
| 随机噪点 | 强度 0.5-2%, 每30-90秒随机切换 | cv2.randn + addWeighted |
| 微抖动 | ±1-3px 随机偏移, 每15-45秒换方向 | cv2.warpAffine 平移 |
| 亮度波动 | ±2-5%, 平滑渐变 | cv2.convertScaleAbs alpha调整 |
| 色温漂移 | ±3% 暖/冷, 缓慢波动 | 调整 B/G 通道比例 |
| 随机抽帧 | 1-3% 帧丢弃, 用前一帧填充 | 遍历帧时按概率跳过 |
| 对比度微调 | ±2-4%, 随机 | cv2.convertScaleAbs |
| 锐度微变 | 高斯模糊半径0-1px随机 | cv2.GaussianBlur |

### 架构要求
- 单文件: `phs/engines/frame_randomizer.py`
- 类名: `FrameRandomizer`
- 方法: `process_video(input_path, output_path, config=None)` → 返回处理后的视频路径
- 方法: `process_frame(frame, config)` → 实时处理单帧（给 OBS 直播用）
- config 为 dataclass，所有参数可调
- 支持 `--dry-run` 模式：只打印会做什么，不实际处理

### 参考代码
- `D:\Code\real-time-video-effects\video_processor.py` — 实时帧处理架构
- `D:\Code\AugLy\augly\video\transforms.py` — AddNoise/Blur/Brightness/ColorJitter transforms

## 模块 2: 音频环境模拟

### 输入
- 音频文件路径 (wav/mp3)
- 背景音文件路径（可选，默认用内置的咖啡厅/街道白噪声）

### 处理

| 效果 | 参数 | 实现方式 |
|------|------|---------|
| 背景音混入 | -35dB, 随机选背景 | librosa 加载+混音 |
| 音调微变 | ±0.2-0.5 半音, 每段随机 | librosa.effects.pitch_shift |
| 随机微静音 | 0.1-0.3秒, 概率5%/分钟 | numpy 置零 |
| 音量波动 | ±1-2dB, 平滑 | 包络线调整 |

### 架构要求
- 单文件: `phs/engines/audio_environment.py`
- 类名: `AudioEnvironmentSimulator`
- 方法: `process_audio(input_path, output_path, config=None)` → 返回路径
- 生成内置白噪声/咖啡厅背景音（如果未提供背景文件）
- config 为 dataclass

## 模块 3: 合成管线入口

### 要求
- 单文件: `phs/engines/live_preprocessor.py`
- 类名: `LivePreprocessor`
- 方法: `process(input_video, output_dir)` → 调用 FrameRandomizer + AudioEnvironmentSimulator + 合成
- 从视频中分离音频 → 处理音频 → 合并回视频
- 使用 ffmpeg 做音视频分离/合并（调用 subprocess）

## 验收标准
1. 处理前后视频时长一致（误差 <0.5秒）
2. 处理前后视觉差异肉眼可见但不过度（像真实拍摄波动）
3. 处理前后音频听起来自然（不像机器人）
4. 每个模块可独立运行和测试
5. `python -m phs.engines.live_preprocessor --input test.mp4 --output-dir D:\PHS\prism\runs\` 能跑通
6. 代码有 type hints, docstring, 基础错误处理
7. 不依赖 GPU，纯 CPU 运行

## 输出格式
- 3 个 Python 文件，放在 `D:\PHS\prism\phs\engines\` 下
- 1 个 `__init__.py` 更新（加 exports）
- 1 个 `test_live_preprocessor.py` 基础测试
- 代码风格匹配 PHS 现有代码（`from __future__ import annotations`, dataclass, type hints）

## 禁止项
- 不要引入新的重型依赖（只用 opencv/numpy/librosa/soundfile/subprocess）
- 不要修改 PHS 现有代码
- 不要写 GUI
- 不要用 torch/gpu
- 不要超过 500 行/文件

## 风险
- ffmpeg 音视频分离可能失败（检查 subprocess 返回码）
- 大视频内存占用（用分段处理）
- 帧处理速度（目标是 >15fps 实时）
