# GPT-5.5 协作管道

## 流程

```
DeepSeek 遇到硬骨头
        ↓
写 queue\YYYYMMDD-HHMMSS-task.md (Review Packet 格式)
        ↓
copy 内容到 from-gpt55.md 顶部，标注 task_id 和状态
        ↓
老板贴给 GPT-5.5 网页 → 回复贴回 from-gpt55.md
        ↓
DeepSeek 读取 from-gpt55.md → 整合执行
        ↓
归档 to/from 到 archive\
```

## 目录

| 目录 | 用途 |
|------|------|
| `queue/` | 待处理的 Review Packet |
| `archive/` | 已完成任务的归档 |
| `templates/` | Review Packet 模板 |
| `to-gpt55.md` | 当前待发送的 prompt（快速通道） |
| `from-gpt55.md` | GPT-5.5 回复（快速通道） |
| `state.json` | 当前任务状态跟踪 |
| `watch-gpt55.ps1` | 剪贴板半自动 watcher |
