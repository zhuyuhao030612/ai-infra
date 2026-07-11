---
name: phs-mirage-audit-checklist
description: GPT-5.5 Mirage代码审计标准——对比AB-Video-Deduplicator + python-audio-separator源码
metadata:
  type: reference
---

## 审计维度

### AB 混合模块 对比 toki-plus 源码
- [ ] 使用 get_a_positions() 算法 (60/120/240fps)
- [ ] 使用 ffmpeg pipe 读帧 (比 OpenCV VideoCapture 快10x)
- [ ] 使用 subprocess 写帧 (比 cv2.VideoWriter 可靠)
- [ ] ffmpeg 有超时+错误处理
- [ ] GPU NVENC 支持 (h264_nvenc)
- [ ] B帧循环 itertool.cycle (不重复解码)
- [ ] 音频从A视频复制 (copy codec)

### 变体工厂 对比 ffmpeg 最佳实践
- [ ] 裁剪: 6种 (center/left/right/top/bottom/zoom)
- [ ] 调色: colorbalance/eq 滤镜
- [ ] 变速: atempo 保音调
- [ ] 水平翻转: hflip
- [ ] 子进程超时+stderr捕获
- [ ] 并行处理 (multiprocessing/concurrent.futures)

### 音频裂变 对比 python-audio-separator API
- [ ] 正确使用 Separator 类
- [ ] 人声/BGM 分离
- [ ] 独立处理参数 (音调/速度)
- [ ] 立体声延时差 (adelay)
- [ ] 降级方案 (ffmpeg基础处理)
- [ ] 错误时返回原音频

### 调度器 对比 OBS WebSocket 协议
- [ ] WebSocket 连接带重试
- [ ] 同片段间隔≥30分钟
- [ ] 同变体不连续
- [ ] 60分钟插入真人标记
- [ ] JSON 输出供外部使用

### 通用质量标准
- [ ] <200行/文件
- [ ] type hints + dataclass
- [ ] subprocess 超时处理
- [ ] GPU flag 可选
- [ ] CLI 入口可独立运行
