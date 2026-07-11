# Third Party Skill Audit: anthropic-skills (claude-code)

## Source
- URL: https://github.com/anthropics/claude-code.git
- commit/tag: 01f1617f14452ac78bf319cef2236d87c0fe05cb
- downloaded_at: 2026-06-28
- reviewer: DeepSeek V4 (automated)
- note: sparse checkout — only `skills/` and `plugins/examples/`

## Verdict
- [X] CONDITIONAL PASS

## Scope
- approved_scope: 仅可参考 plugins/examples/ 中的 skill 写法
- copied_files: 无
- forbidden_files: plugins/ 下所有 .js/.ts 运行时文件（不得执行）
- required_redactions: 移除读取 secrets、修改全局配置的指令（如有）

## Key Findings
| severity | item | evidence | decision |
|---|---|---|---|
| P1 | plugins/ 下有 .js/.ts 运行时 | 可能含 exec/child_process | 不得执行 |
| OK | LICENSE.md 存在 | - | 通过 |
| OK | 无 shell 脚本 | - | 通过 |
| OK | 稀疏检出仅 50 个文件 | 已排除 artifacts | 通过 |

## Decision
- 是否允许进入 skills/approved/：否
- 是否允许执行脚本：否
- 是否允许提取纯 Markdown 规则：是（plugins/examples/ 中的写作范式）
- 是否需要 GPT-5.5 复核：是（提取前必须复核；所有 JS/TS 插件运行时 forbidden；只允许参考 Markdown 写法）
- 下次更新是否需要重审：是

## Note
此仓库主要是 Claude Code CLI 源码，经过稀疏检出只保留了 skills/ 和 plugins/examples/。研究价值在于学习 Anthropic 官方的 skill 写作规范，而非直接使用其代码。
