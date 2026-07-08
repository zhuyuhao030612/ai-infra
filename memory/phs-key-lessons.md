---
name: phs-key-lessons
description: PHS Prism Studio 实战教训7条——RTX5060Ti/PyTorch兼容/OBS WebSocket/OpenCV API变更/代码编辑/管道不可靠 (2026-07-08 从LESSONS_LEARNED.md提取)
metadata:
  type: feedback
---

## PHS 项目关键教训

> 来源：`D:/PHS/prism/docs/LESSONS_LEARNED.md`

### 1. RTX 5060 Ti Blackwell sm_120 — PyTorch 兼容
**问题**：PyTorch 2.6.0+cu124 不支持 Blackwell (sm_120)，报 `no kernel image is available`
**解决**：升级 PyTorch 2.12.1+cu132
```bash
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu132 --reinstall --system
```
**根因**：5060 Ti 是 2026 新架构，pip 默认源只有 CPU 版 wheel

### 2. PyTorch CDN 哈希校验失败
**问题**：pip install 从 download.pytorch.org 下载 CUDA wheel 哈希不匹配
**解决**：用 `uv pip install` 替代 `pip install`，uv 的下载和缓存机制不受影响

### 3. OBS WebSocket 连接失败
**问题**：Python websockets 连接报 ConnectionRefusedError
**解决**：OBS→工具→WebSocket服务器设置→启用→关闭认证(auth_required: false)。用 async websockets 而非 obsws-python
**根因**：OBS WebSocket 默认关闭

### 4. Launcher 在用户机器上闪退
**问题**：安装后双击闪退无提示
**解决**：Launcher 不再 import 任何 app 模块→改为 subprocess 调用；所有异常写入 reports/launcher_crash.log；打包 PHS_Launcher.exe (PyInstaller standalone)
**根因**：Launcher import 了 app 模块导致用户缺少 numpy/cv2 时 crash

### 5. OpenCV MSER API 变更
**问题**：`cv2.MSER_create(_min_area=30)` 在 OpenCV 4.11 报错
**解决**：改用 setter 方法
```python
mser = cv2.MSER_create()
mser.setMinArea(30); mser.setMaxArea(w*h//8)
```

### 6. 代码编辑工具累积错误
**问题**：多次小编辑导致缩进混乱、重复行、语法错误
**解决**：编辑超过 5 次时，直接重写整个文件，不要继续修补

### 7. GPT-5.5 管道不可靠
**问题**：多次返回 GPT_UNAVAILABLE 或超时
**解决**：重试；超过 2 次失败则自己做决策，不等管道

### 8. 纯合成数据泛化不到真实场景（水印训练）
**问题**：合成数据训练 IoU 0.999 但泛化到真图失败
**解决**：用项目自有视频抽帧做背景叠加合成水印再微调；全内存 OnTheFlyDataset 比文件 I/O 可靠；AMP + BCEWithLogits 不兼容→小模型用 FP32

### 9. GPU-first 零 CPU fallback
Florence-2 小模型比 LTX-Insight 大模型更实用。先深度研究再动手，不要上来就写代码。

### 10. HuggingFace 大文件下载不稳定
需梯子+镜像。大权重文件（CosyVoice 4.4GB, SAM2 857MB）下载是高风险步骤。

**Why:** 避免重复踩坑。这些教训是实战血泪。
**How to apply:** 遇到类似场景先查此列表。RTX5060Ti→cu132，OBS→开WebSocket关auth，编辑超5次→重写文件，管道不可靠→2次失败自己做。
