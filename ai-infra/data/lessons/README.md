# 经验数据库

自动和手动收集的故障经验。每条经验包含：

- **现象**：什么错了
- **触发条件**：什么时候发生
- **根因**：为什么错
- **修复**：怎么修好的
- **预防**：下次怎么避免
- **标签**：关键词用于检索

## 索引

见 `D:\Code\ai-infra\scripts\lessons-search.ps1` 的检索逻辑。

## 文件格式

```markdown
---
tags: [powershell, encoding, utf-8]
date: 2026-06-27
source: P1-2 verify.ps1
---

# Python open() GBK 编码错误

**现象**：UnicodeDecodeError: 'gbk' codec can't decode byte 0x94
**触发**：Windows 中文版，Python open() 不带 encoding 参数
**根因**：Python 在中文 Windows 上默认 locale 编码是 GBK
**修复**：open(path, encoding='utf-8')
**预防**：所有 Python 文件操作都显式指定 encoding='utf-8'
```
