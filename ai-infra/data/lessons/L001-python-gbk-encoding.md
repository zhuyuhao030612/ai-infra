---
tags: [python, encoding, windows, utf-8, gbk, powershell, path]
match_keywords: [python encoding, utf-8, gbk, 编码, 中文路径, 乱码, powershell path, unicode decode error, open file]
date: 2026-06-27
source: P1-2 verify.ps1
severity: medium
status: final
---

# Python open() GBK 编码错误

**现象**：`UnicodeDecodeError: 'gbk' codec can't decode byte 0x94`

**触发条件**：
- Windows 中文版（系统 locale 是 GBK）
- Python `open()` 不带 `encoding` 参数
- 文件内容是 UTF-8，包含中文或特殊字符

**根因**：Python 的 `open()` 默认用系统 locale 编码。中文 Windows = GBK。UTF-8 文件的中文字节被当成 GBK 解码。

**修复**：`open(path, encoding='utf-8')`

**预防**：所有 Python 文件 I/O 都显式指定 `encoding='utf-8'`

**关联**：
- PowerShell 路径传给 Python 时，反斜杠也会出问题：用 `$path -replace '\\', '/'` 转成正斜杠
- 见 [[windows-pitfalls]]
