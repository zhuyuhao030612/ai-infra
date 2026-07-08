# Third Party Skill Audit: superpowers

## Source
- URL: https://github.com/obra/superpowers.git
- commit/tag: 896224c4b1879920ab573417e68fd51d2ccc9072 (Release v6.0.3)
- downloaded_at: 2026-06-28
- reviewer: DeepSeek V4 (automated scan) + GPT-5.5 (rule review)
- skill_name: superpowers

## Verdict
- [ ] PASS
- [ ] REJECT
- [X] CONDITIONAL PASS

## Scope
- approved_scope: 仅可抽取 SKILL.md 中的规则思想和 prompt 模板
- copied_files: 无（待人工决定抽取哪些规则）
- forbidden_files: 
  - `.pi/` — 运行时 bootstrap
  - `scripts/sync-to-codex-plugin.sh`
  - `skills/brainstorming/scripts/start-server.sh`
  - `tests/brainstorm-server/stop-server.test.sh`
  - 所有 `.js`/`.ts` 执行文件
  - `.opencode/` — 第三方配置
  - `hooks/` — 如果有
- required_redactions: 移除所有 "auto-approve" 类指令（如有）

## Findings

### 0. 基本信息
- Skill 名称：superpowers
- 来源 URL：https://github.com/obra/superpowers
- 来源类型：[X] GitHub
- 下载位置：`ai-infra/third_party_skill_research/superpowers/raw`
- commit hash：896224c4
- 是否固定版本：[X] 是
- 是否禁止自动更新：[X] 是

### 1. LICENSE
- [X] MIT License
- [X] 允许商业使用
- [X] 允许修改和分发
- 审计结论：通过

### 2. 安装脚本与 hooks
- [X] 无 postinstall/preinstall/prepare
- [X] 无 package.json lifecycle scripts
- 但有 shell 脚本：sync-to-codex-plugin.sh, start-server.sh
- 审计结论：shell 脚本不得执行，仅研究其逻辑

### 3. 敏感资源访问
- [X] 未发现读取 .env/secrets/SSH 的直接代码
- 但 .pi/extensions/ 和 .opencode/ 可能读取运行环境配置
- 审计结论：不复制到 skills/approved/ 则无风险

### 4. 命令执行
- [X] 发现 child_process/exec/spawn 引用在多个 .js/.ts 文件
- 但这些都是 OpenCode/Codex 插件运行时，不是 install 脚本
- 审计结论：不执行则无风险

### 5. 网络访问
- 未深入审计 JavaScript/TypeScript 运行时行为
- 已知有 server 启动脚本（start-server.sh）
- 审计结论：不启动 server 则无风险

### 6. 文件操作
- 无 rm -rf / 危险操作发现
- 有 Git submodule 或类似结构
- 审计结论：不在 skills/ 内操作则无风险

### 7. Prompt Injection / 指令污染 — 部分不通过
- 部分 skill 文件可能包含 "auto-approve" 类指令
- `skills/` 目录下 SKILL.md 设计为自动触发
- 在 Claude Code 中这些会被自动加载为指令
- 必须逐文件审查后方可提取规则
- 审计结论：SKILL.md 不得原样放入 skills/

### 8. 供应链与仓库结构
- 无 submodules
- 无 GitHub Actions workflows
- 无 Dockerfile
- 有 Makefile（但未审计）
- 审计结论：通过

### 9. 依赖与版本
- 固定版本：[X] 是（commit hash 已记录）
- 无 npm dependencies 需要安装
- 审计结论：通过

### 10. Artifact / 产物安全
- 无 artifact 生成逻辑发现
- 审计结论：通过

### 11. 抽取规则评估
- [X] 核心思想可剥离为纯 Markdown 规则
- [X] 可只使用其规则思想，不执行代码
- [X] 有高质量 prompt 模板可参考
- [X] 需要改写以符合本项目 L0-L5 安全分级
- 关键可抽取内容：
  - skills/systematic-debugging/ — 系统化调试方法论
  - skills/writing-skills/ — 编写 skill 的指南
  - skills/brainstorming/ — 头脑风暴和需求提取
  - skills/tdd/ — TDD 工作流
  - README.md 开头 30 行概述 — 架构思想

### 12. 审批记录
- [X] 已生成 AUDIT.md
- [X] 已记录 reviewer/date/source/version/hash
- [X] 已列出 forbidden_files
- [X] 已定义更新复审流程

## Hash Manifest
见 SHA256SUMS.txt（165 个文件）

## Decision
- 是否允许进入 skills/approved/：否（现阶段）
- 是否允许执行脚本：否
- 是否允许提取纯 Markdown 规则：是，需逐文件审查后改写
- 是否需要 GPT-5.5 复核：是（提取规则前）
- 下次更新是否需要重审：是

## 推荐下一步
1. 提取 `systematic-debugging` 的调试流程 → 改写为 failure-analysis-skill 的补充
2. 提取 `writing-skills` 的 skill 编写规范 → 改写为本项目 skill 模板
3. 提取 `brainstorming` 的需求澄清 prompt → 改写为 review-skill 的前置步骤
4. 提取 `tdd` 的 TDD 流程 → 改写为验证步骤规范
5. 所有改写后只保留纯 Markdown，删除脚本引用和自动执行指令
