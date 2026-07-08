# Spec: PHS Mirage 裂变管线

## 背景
PHS 需要 24x7 无人直播。2小时原始素材 → 裂变成168小时不重复内容。
已有基础设施: frame_randomizer, audio_environment, live_preprocessor, OBS WebSocket。

## 现成的开源组件（直接用，不要重新实现）

| 组件 | 路径 | 核心API |
|------|------|---------|
| AB-Video-Deduplicator | D:/Code/AB-Video-Deduplicator/src/main.py | `get_a_positions(fps, N_a)` + `frame_reader()` + ffmpeg pipe |
| ffmpeg | 系统自带 | crop/color/speed/mirror/volume/pitch |
| python-audio-separator | pip install audio-separator | `Separator().load_model()` → `.separate()` |
| PHS frame_randomizer | phs/engines/frame_randomizer.py | `FrameRandomizer().process_video()` |
| PHS audio_environment | phs/engines/audio_environment.py | `AudioEnvironmentSimulator().process_audio()` |

## 要求: 写 5 个胶水模块 (每个 <200 行)

### 模块 1: `phs/mirage/scene_splitter.py`
- 用 ffmpeg scene detect 把视频切成片段
  ```python
  ffmpeg -i input.mp4 -vf "select='gt(scene,0.3)',showinfo" -vsync vfr segments/%03d.mp4
  ```
- 输出: 每个片段 30-90 秒, 放在 temp 目录
- 函数: `split_scenes(input_path, output_dir, min_sec=30, max_sec=90) -> list[Path]`
- 去重相邻相似片段

### 模块 2: `phs/mirage/variant_factory.py`
- 对每个片段生成变体矩阵
- 参数矩阵: crop(6) × color_temp(3) × speed(3) × hflip(2) = 108
- 用 ffmpeg 子进程, 支持 GPU (NVENC) 可选
- 函数: `generate_variants(segment_path, output_dir, variants_per_segment=108) -> list[Path]`
- 裁剪 6 种: center/left/right/top/bottom/zoom
- 调色 3 种: warm(+5%红)/cool(+5%蓝)/none
- 速度 3 种: 0.95x/1.0x/1.05x (用 atempo 保音调)
- 镜像 2 种: none/hflip

### 模块 3: `phs/mirage/ab_mixer.py`
- 封装 AB-Video-Deduplicator 的核心算法
- 导入 `get_a_positions` 和 `frame_reader` 逻辑
- 为每个变体视频混入随机诱饵帧
- 诱饵视频来源: samples/ 目录下的无关视频
- 函数: `mix_frames(video_a, video_b, output_path, fps=240, gpu=True) -> Path`
- 支持多诱饵视频随机选择

### 模块 4: `phs/mirage/audio_cracker.py`
- 用 python-audio-separator (Demucs) 分离人声/BGM
- 人声: 音调±0.3半音 + 速度±3%
- BGM: 降采样32kHz + FFT随机衰减(-3dB~+1dB)
- 立体声延时差: 左声道+17ms, 右声道+23ms
- 叠加环境音(-35dB) → PHS已有 audio_environment 做这个
- 重混音输出
- 函数: `crack_audio(input_path, output_path, config) -> Path`
- 如果 audio-separator 不可用, 降级为 ffmpeg 基础处理

### 模块 5: `phs/mirage/scheduler.py`
- 生成随机播放列表
- 防重复: 同片段间隔≥30分钟, 同变体不连续
- 每60分钟插入"真人互动"标记事件
- 通过 OBS WebSocket (obs-websocket-js 或 Python obsws-python) 控制场景切换
- 函数: `generate_playlist(variants, output_dir, target_hours=168) -> list[dict]`
- 函数: `push_to_obs(playlist, obs_host="localhost:4455", obs_password="...")`
- 输出 JSON 调度文件供外部使用

## 集成入口: `phs/mirage/__init__.py`
```python
class MiragePipeline:
    def run(self, input_video: Path, output_dir: Path, 
            target_hours: int = 168, gpu: bool = True, 
            variant_count: int = 100) -> Path:
        """一键裂变: 输入2小时 → 输出168小时素材包"""
```

## 验收标准
1. 每个模块独立可运行, 有 CLI 入口 (`python -m phs.mirage.xxx --input ... --output ...`)
2. 不引入超过 3 个新 pip 依赖
3. 所有外部进程调用有超时+错误处理
4. GPU 加速可选 (NVENC flag)
5. `MiragePipeline.run()` 端到端可跑通
6. 代码风格匹配 PHS 现有规范 (from __future__ import annotations, dataclass, type hints)
7. 每个文件 <200 行

## 禁止
- 不要重新实现 AB 算法 (直接用 toki-plus)
- 不要自己写 Demucs 封装 (直接用 audio-separator)
- 不要写 GUI
- 不要修改 PHS 现有代码
- 不要超过 200 行/文件

## 输出格式
5 个 .py 文件 + 1 个 __init__.py, 放在 phs/mirage/ 下
