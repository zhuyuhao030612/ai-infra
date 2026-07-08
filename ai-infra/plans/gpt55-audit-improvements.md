# GPT-5.5 审计改进实施计划

## Context

GPT-5.5 对 Claude Code (DeepSeek V4 Pro) 做了审计，诊断核心问题：**行动先于证据、失败模式未固化为硬阻断、任务状态不是机器可读**。三个改进方向：证据驱动执行器、最小回归+负向安全测试、机器可读任务状态机。

**原则：增强现有，不重建。所有脚本必须通过 ps-guard。**

---

## Phase 1: 机器可读任务状态机（基础）

其他两个方向依赖此阶段。

### 新建

| 文件 | 说明 |
|---|---|
| `ai-infra\schemas\task-schema.json` | JSON Schema Draft 2020-12，定义 task.json 必需/可选字段、transitions 数组、level 约束 |
| `ai-infra\scripts\state-transition.ps1` | 状态转换引擎：pending→running→completed/failed/blocked，用 Test-ValidTransition 校验，输出结构化 JSON |

### 修改

| 文件 | 改动 |
|---|---|
| `ai-infra\automation\submit-task.ps1` | 输出加 `schema_version`、`transitions` 初始记录、`evidence_path` |
| `ai-infra\scripts\new-run.ps1` | run 目录下创建 `task.json`（含 status=running + transitions）、空 `evidence.jsonl` |
| `ai-infra\scripts\close-run.ps1` | 关闭时更新 task.json status→completed/failed，记录 result 和 evidence_count |
| `ai-infra\scripts\state-sync.ps1` | state.json 加 `recent_runs[]`（最近5个 task.json 摘要）、`state_machine_version` |
| `ai-infra\automation\run-task.ps1` | 用 state-transition.ps1 管理状态，替代手动文件操作 |

### 验证

```powershell
# 状态转换测试
state-transition.ps1 -TaskId test -From pending -To running    # expect 0
state-transition.ps1 -TaskId test -From pending -To completed  # expect 1 (非法跳转)
# 完整链路
submit-task.ps1 → new-run.ps1 → 检查 task.json + evidence.jsonl → close-run.ps1 → 检查 status=completed
```

---

## Phase 2: 证据驱动执行器

依赖 Phase 1 的 evidence.jsonl 和 run 目录结构。

### 新建

| 文件 | 说明 |
|---|---|
| `ai-infra\scripts\evidence-check.ps1` | 可调用证据验证：-Operation (validate/read-before-write/schema-check) -Target，输出 `{ok, reason, evidence[]}`，exit 0=pass 1=fail |
| `ai-infra\scripts\post-tool-recorder.ps1` | PostToolUse hook：读 stdin JSON，提取 tool_name + input_hash + file_paths，写 evidence.jsonl 一行，静默，永远 exit 0 |

### 修改

| 文件 | 改动 |
|---|---|
| `ai-infra\hooks\pretool-guard.ps1` | 加 `$warnPatterns` 软阻断层（允许但记录）；加 `ghp_*` GitHub PAT 检测；对 Write/Edit 加路径上下文启发式检查 |
| `ai-infra\scripts\ai-start.ps1` | 高风险任务类型加"运行 evidence-check.ps1"强制步骤 |
| `ai-infra\scripts\new-run.ps1` | Phase 1 已建 evidence.jsonl，确认初始化正确 |

### 验证

```powershell
evidence-check.ps1 -Operation validate -Target "不存在的文件"  # expect fail
# 模拟 Write 工具调用 JSON 通过 pretool-guard → expect allow
# 模拟 Remove-Item 调用 → expect deny + 结构化原因
# 验证 evidence.jsonl 有新条目
ps-guard.ps1 evidence-check.ps1 && ps-guard.ps1 post-tool-recorder.ps1  # 都必须 PASS
```

---

## Phase 3: 回归 + 负向安全测试

依赖 Phase 1+2 的基础设施。

### 新建

| 文件 | 说明 |
|---|---|
| `ai-infra\smoke\test-permissions.ps1` | 7 个 L0-L5 权限测试：L0/L1/L2 允许，L3 无 risk_ack 拒绝，L3 有 risk_ack 允许但记录，L4/L5 永远拒绝。纯模拟不实际操作 |
| `ai-infra\smoke\test-psguard.ps1` | 6 个 ps-guard 边缘测试：合法脚本 PASS、缺 StrictMode WARN、iex FAIL、硬编码C盘 FAIL、Bearer token FAIL、risk_ack=true FAIL |

### 修改

| 文件 | 改动 |
|---|---|
| `ai-infra\smoke\test-safety.ps1` | 加 test 7（redact 脱敏验证）、test 8（new-run 创建 evidence.jsonl 验证） |
| `ai-infra\smoke\test-negative-paths.ps1` | 加 3 个测试：evidence-check 缺参报错、post-tool-recorder 坏 JSON 优雅降级、pretool-guard 拦截 ghp_ token |
| `ai-infra\smoke\run-all.ps1` | 加 section 6（test-permissions）、7（test-psguard）、8（evidence 存在性检查） |

### 验证

```powershell
# 全部通过
pwsh -File D:\Code\ai-infra\smoke\run-all.ps1
# 所有新脚本 ps-guard 通过
foreach ($s in @("evidence-check","post-tool-recorder","state-transition","test-permissions","test-psguard")) {
  pwsh -File D:\Code\ai-infra\scripts\ps-guard.ps1 -Path "D:\Code\ai-infra\scripts\$s.ps1"
}
```

---

## 文件清单

**新建 6 个**：
- `D:\Code\ai-infra\schemas\task-schema.json`
- `D:\Code\ai-infra\scripts\state-transition.ps1`
- `D:\Code\ai-infra\scripts\evidence-check.ps1`
- `D:\Code\ai-infra\scripts\post-tool-recorder.ps1`
- `D:\Code\ai-infra\smoke\test-permissions.ps1`
- `D:\Code\ai-infra\smoke\test-psguard.ps1`

**修改 10 个**：
- `D:\Code\ai-infra\hooks\pretool-guard.ps1`
- `D:\Code\ai-infra\scripts\ai-start.ps1`
- `D:\Code\ai-infra\scripts\new-run.ps1`
- `D:\Code\ai-infra\scripts\close-run.ps1`
- `D:\Code\ai-infra\scripts\state-sync.ps1`
- `D:\Code\ai-infra\automation\submit-task.ps1`
- `D:\Code\ai-infra\automation\run-task.ps1`
- `D:\Code\ai-infra\smoke\test-safety.ps1`
- `D:\Code\ai-infra\smoke\test-negative-paths.ps1`
- `D:\Code\ai-infra\smoke\run-all.ps1`

---

## 风险

| 风险 | 应对 |
|---|---|
| PostToolUse hook 不支持 | 降级为模型协议强制，跳过 hook 文件 |
| state-transition 阻塞自动化 worker | 增量调用，不替代现有文件操作，失败被现有错误处理捕获 |
| test-permissions 因工具格式变更脆弱 | 测试用 hooks 真实接收的 JSON 格式，格式变则更新测试 |
| new-run.ps1 改动破坏现有初始化 | 纯增量（加 JSON 不改 Markdown），回滚只需删 task.json 创建 |
