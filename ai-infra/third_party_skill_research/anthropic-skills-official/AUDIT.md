# Third Party Skill Audit: anthropic-skills-official

## Source
- URL: https://github.com/anthropics/skills.git
- commit/tag: 35414756ca55738e050562e272a6bbc6273aa926
- downloaded_at: 2026-06-28
- reviewer: DeepSeek V4 (automated)

## Verdict
- [X] CONDITIONAL PASS

## Scope
- approved_scope: 仅抽取 SKILL.md 中合规的规则和 prompt 模板
- copied_files: 无
- forbidden_files: skills 目录以外的所有 spec/template/ 文件（未审计）
- required_redactions: 移除自动执行、auto-approve、读取 secrets 的指令（如有）

## Key Findings
| severity | item | evidence | decision |
|---|---|---|---|
| P1 | skills/ 目录可直接被 Claude Code 加载 | 顶层的 `skills/` 就是加载路径 | 研究时只能作为 data |
| P2 | 414 个文件未全部审计 | 有 spec/template/ 等辅助目录 | 先只审计 skills/ 下内容 |
| OK | LICENSE 存在 | Apache 2.0 | 通过 |
| OK | 无 install scripts | 无 postinstall/preinstall | 通过 |
| OK | 无 shell 脚本 | find 未发现 .sh/.ps1 | 通过 |

## Decision
- 是否允许进入 skills/approved/：否
- 是否允许执行脚本：不适用
- 是否允许提取纯 Markdown 规则：是，仅限 `skills/` 下经审计的 SKILL.md
- 是否需要 GPT-5.5 复核：是
- 下次更新是否需要重审：是

## Note
此仓库为 Anthropic 官方 skills 集合。安全风险最低，但仍有 prompt injection 风险——需要逐文件检查是否含 "忽略安全策略"、"自动批准"、"读取 secrets" 类指令。414 个文件中大部分是 spec/ 目录下的规范文档，与 skills 无关。skills/ 目录本身相对干净。
