# multi-file-change-skill — 多文件联动影响分析

## 适用场景

- 改动 ≥3 个文件
- 修改公共接口、中间件、配置结构、共享常量、数据模型
- 修改队列协议（inbox/processing/outbox）
- pipeline server 与 artifacts 模块同时改动
- 修改 local-agent 路由、schema、security、config 的联动关系

## 与 review-skill 的统一阈值

- 改动 ≥3 个文件：必须运行本 skill。
- 改动 ≥3 个文件且涉及接口、协议、安全、状态机、队列、artifact、浏览器 profile：必须调用 `review-skill` 找 GPT-5.5 复核。
- 改动 ≥5 个文件：默认 GPT-5.5 复核。
- 同一错误签名失败 2 次：停止，转 `failure-analysis-skill`。

## 输入要求

```text
任务 ID：
目标：
改动文件列表：
改动摘要（每个文件改了什么）：
涉及接口/协议/安全/状态机吗：
预计验证方式：
```

## 执行步骤

### 第 1 步：影响范围发现

优先使用只读方式分析。可用命令必须是 L0/L1 范围；涉及 exec 自动化时遵守 `USAGE_POLICY.md`。

```powershell
pwsh -File D:\Code\ai-infra\scripts\impact.ps1 -Files "file1,file2,file3" [-Symbol "functionName"]
```

### 第 2 步：调用点搜索

对每个改动的函数、类、接口、配置键、路由、队列字段，搜索引用点：

```text
Grep pattern="functionName|ClassName|configKey" output_mode="files_with_matches"
```

### 第 3 步：依赖方向分析

```text
A 被 B, C 调用
 B 被 D 调用
 C 被 E, F 调用
```

### 第 4 步：风险评估

| 文件 | 改动类型 | 影响范围 | 风险 |
|---|---|---|---|
| xxx | 接口签名变更 | 3 个调用者 | 高 |
| yyy | 内部重构 | 仅自身 | 低 |

### 第 5 步：分批执行策略

- 允许整体规划 ≥3 个文件。
- 禁止一次性无验证地提交 ≥3 个文件。
- 每批建议 1-2 个文件。
- 每批完成后运行对应验证。
- 先改被调用者，再改调用者。
- 先改 schema/config，再改使用方。
- 协议变更必须同时更新生产者、消费者、测试、文档。

## 输出路径

```text
ai-infra/reports/multi-file/<YYYYMMDD-HHMMSS>-<task-id>.md
```

## 输出格式

```markdown
# 多文件联动报告

## 改动计划
[文件列表 + 顺序 + 批次]

## 影响范围
[依赖图]

## 风险点
| 严重度 | 文件 | 风险 | 缓解 |
|---|---|---|---|

## 分批策略
- Batch 1:
- Batch 2:

## 验证步骤
[每个文件的验证方法 + 整体集成验证]

## 是否触发 GPT-5.5
- [ ] 改动 ≥3 且涉及接口/协议/安全/状态机
- [ ] 改动 ≥5
- [ ] 未触发，原因：
```

## 禁止行为

- 跳过影响分析直接改
- 一次性无验证提交 ≥3 个文件
- 不写回归测试就宣布完成
- 只验证 happy path
- 改协议不更新消费者
- 改 schema 不更新调用方
- 涉及安全边界却不走 security-gate

## 验证步骤

1. 确认无遗漏调用点
2. 每批修改后运行语法检查：`ruff check` / `node --check` / 类型检查
3. 跑相关单测或冒烟测试
4. 整体验证生产者/消费者协议
5. 若触发阈值，发 GPT-5.5 复核
6. 验证结果写入报告

## 失败停止条件

- 影响范围超出预期 → 停止，重新规划
- 发现新的调用点未被处理 → 停止，更新影响分析
- 测试失败且无法快速定位 → 生成 failure-analysis
- 涉及 L3+ 操作但无人类确认 → 停止
