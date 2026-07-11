---
name: security-gate-skill
description: 安全门禁 — 写入前14条规则扫描，防止secret/token泄露到代码或记忆
version: 1.0.0
---
# security-gate-skill — 安全门禁

## 适用场景

- 修改 `local-agent` 路由，特别是 `/exec`、`/files`、`/desktop`
- 修改 `local-agent/app/security.py`
- 修改 `gpt55-server.js` 的凭据、会话、队列、artifact、浏览器 profile 处理
- 引入新依赖（npm/pip/uv/cargo）
- 暴露新端口或网络接口
- 修改 artifact 下载逻辑
- 涉及 token、password、cookie、SSH key、浏览器 profile
- L3/L4/L5 操作

## 裁决执行规则

- 门禁报告必须写入：`ai-infra/security-reviews/<YYYYMMDD-HHMMSS>-<task-id>.md`
- 未生成门禁报告视为未通过。
- P0/P1 不允许有条件通过，必须修复后重审。
- P2 可以有条件通过，但必须记录条件、责任人、截止时间和回归验证。
- GPT-5.5 复核为“不通过”时必须停止。
- GPT-5.5 复核不是人类授权；L3+ 仍需人类确认。
- agent 不得自签门禁，不得自行填写 `risk_ack=true`。

## 输入要求

```text
任务 ID：
改动文件：
改动内容摘要：
涉及的安全边界：
操作等级：L0/L1/L2/L3/L4/L5
当前防护措施：
是否需要人类确认：
是否已脱敏：
```

## 安全检查项

### 鉴权

- [ ] Token 是否使用常量时间比较（如 `hmac.compare_digest`）
- [ ] Token 是否从环境变量读取，不硬编码
- [ ] Token 是否不会进入日志、错误信息、状态文件
- [ ] 高风险操作是否有二次 token 或等效机制
- [ ] `risk_ack` 是否只能由人类确认触发，agent 不得自补
- [ ] 鉴权失败是否不会泄露内部状态

### 输入验证

- [ ] 路径是否有 allowlist 沙箱
- [ ] 是否防 `../`、绝对路径、UNC 路径、symlink 逃逸
- [ ] 敏感读取是否至少按 L4 处理
- [ ] 命令参数是否有白名单或 profile 限制
- [ ] 文件数量、单文件大小、总大小是否有限制
- [ ] 请求体大小是否有限制
- [ ] 批量操作是否有 dry-run

### 输出与日志

- [ ] 错误信息是否脱敏
- [ ] 审计日志是否记录关键操作、run_id、操作者
- [ ] API 响应是否不泄露 secrets、内部路径、cookie、token
- [ ] 失败 artifact 是否不会包含敏感截图或 secrets
- [ ] 发给 GPT-5.5 前是否脱敏

### 网络

- [ ] 是否只监听 127.0.0.1
- [ ] CORS 是否严格
- [ ] 是否有速率限制或调用频率限制
- [ ] 是否新增外部访问域名
- [ ] 是否新增 webhook/callback
- [ ] 是否暴露新端口
- [ ] 是否可能被局域网访问

### Exec / SSH / 桌面控制

- [ ] `/exec` 是否限制命令 profile 或 allowlist
- [ ] destructive 命令是否默认阻断
- [ ] SSH 是否需要人类确认
- [ ] 桌面点击/输入是否需要高风险 token 和人类确认
- [ ] 是否禁止 agent 自行升级到高风险操作
- [ ] 是否有 dry-run 或最小影响验证

### 依赖

- [ ] 是否固定版本，不用 `^`、`~`、latest
- [ ] 是否检查 LICENSE
- [ ] 是否检查 install/postinstall/prepare/build hooks
- [ ] 是否有 native/binary/wasm
- [ ] 是否有 known vulnerabilities
- [ ] 是否有 transitive dependencies 风险
- [ ] 是否记录为什么不能用标准库替代

### Artifact 安全

- [ ] 下载文件是否校验 MIME/signature/hash
- [ ] zip/tar 是否防 Zip Slip
- [ ] 是否禁止自动执行 artifact
- [ ] 是否限制文件数量、单文件大小、总大小
- [ ] 是否绑定 request_id / run_id
- [ ] 是否检查 HTML/login page 伪装下载
- [ ] 是否限制 cross-origin 下载
- [ ] artifact 路径是否不含 `../`

### 第三方 Skill 安全

- [ ] 原始仓库是否只在 `third_party_skill_research/`
- [ ] 是否未放入 `skills/` 自动加载路径
- [ ] 是否只复制改写后的纯 Markdown
- [ ] 是否无脚本、二进制、hooks、symlink 进入 approved
- [ ] 是否有独立 AUDIT.md 和 sha256 manifest

## 输出格式

```markdown
# 安全门禁报告

## 基本信息
- 任务 ID：
- 时间：
- 操作等级：
- 审查人：
- 是否需要人类确认：

## 审查范围
[文件列表]

## 发现
| 严重度 | 问题 | 位置 | 修复建议 |
|---|---|---|---|

## P0/P1 清零状态
- [ ] 无 P0
- [ ] 无 P1

## 裁决
- [ ] 通过
- [ ] 有条件通过（仅 P2/P3，列出条件）
- [ ] 驳回

## 人类确认
- 是否需要：[ ] 是 [ ] 否
- 确认来源：
- 确认原文：
- 确认时间：

## 验证步骤
1. ...
```

## 禁止行为

- 不经过安全门禁修改 auth/exec/凭据代码
- 跳过门禁直接部署
- 门禁不通过继续推进
- P0/P1 未修复却条件通过
- agent 自签门禁或自填人类确认
- 用 GPT-5.5 复核代替人类确认
- 把未脱敏 secrets 放入门禁报告

## 验证步骤

1. 对照检查项逐条核实
2. 生成门禁报告
3. 发 GPT-5.5 复核
4. 修复 P0/P1
5. 如需 L3+，取得人类明确确认
6. 重新验证并记录结果

## 失败停止条件

- 发现 P0 → 立即停止
- 发现 P1 → 修复后才能继续
- GPT-5.5 复核不通过 → 停止
- 未生成人类确认但要执行 L3+ → 停止
- 门禁报告缺失 → 视为未通过
