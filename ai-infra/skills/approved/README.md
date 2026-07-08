# Approved Skills Rules

本目录只允许保存经过审计、人工改写后的纯 Markdown 规则。

## 允许

- `SKILL.md`
- 纯 Markdown prompt 模板
- 无脚本、无外部依赖的说明文档

## 禁止

- 第三方仓库整包复制
- shell / PowerShell / Python / Node 脚本
- 二进制、WASM、DLL、EXE
- MCP 配置
- hooks
- symlink / hardlink
- 隐藏 dotfiles
- install 文件
- 未脱敏 secrets

每个 approved skill 必须能追溯到 `third_party_skill_research/<skill-name>/AUDIT.md`。
