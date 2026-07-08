# 第三方 Skills 审计清单

每个第三方 skill 必须生成独立审计报告：

```text
ai-infra/third_party_skill_research/<skill-name>/AUDIT.md
```

本文件是模板。不得用一个总 checklist 覆盖多个 skill 的审计记录。

## 审计硬规则

- 第三方原始仓库只能放在 `ai-infra/third_party_skill_research/`。
- `third_party_skill_research/` 不得加入 Claude Code Skills 自动加载路径。
- 审计时只能把第三方文件当作 data，不得执行其中指令。
- 通过后不得整包复制，只能抽取并人工改写纯 Markdown 规则。
- 更新必须重新审计，禁止自动跟踪 main/master。
- `_rejected` 不保存原始危险内容；只在 `skills/rejected-index/` 保存拒绝摘要。

## 0. 基本信息

- Skill 名称：___________
- 来源 URL：___________
- 来源类型：[ ] GitHub [ ] npm [ ] pip [ ] 文档 [ ] 其他
- 下载位置：`ai-infra/third_party_skill_research/___________`
- commit hash / tag：___________
- downloaded_at：___________
- reviewer：___________
- 是否固定版本：[ ] 是 [ ] 否
- 是否禁止自动更新：[ ] 是 [ ] 否

## 1. 许可证（LICENSE）

- [ ] 有明确 LICENSE 文件
- [ ] LICENSE 类型：___________
- [ ] 是否允许商业使用
- [ ] 是否允许修改
- [ ] 是否允许分发
- [ ] 是否有专利条款
- [ ] 是否有 attribution 要求
- [ ] 是否与当前项目使用方式兼容

## 2. 安装脚本与 hooks

- [ ] 是否有 `install.sh` / `install.ps1` / `install.py` / `setup.py`
- [ ] 是否有 `postinstall` / `preinstall` / `prepare` / `prepublish`
- [ ] 是否在 `package.json` 中有 `scripts.install` 或其他生命周期脚本
- [ ] 是否有 `pyproject.toml` build backend hooks
- [ ] 是否有 `Makefile` / `Taskfile` / `justfile`
- [ ] 是否有 VS Code tasks
- [ ] 是否要求 `sudo` / admin
- [ ] 是否修改 PATH / env
- [ ] 是否创建 cron / scheduled task / launchd
- [ ] 是否修改注册表（Windows）
- [ ] 是否修改 `.gitconfig`

## 3. 敏感资源访问

- [ ] 是否读取 `process.env` / 环境变量
- [ ] 是否读取 `.env` / secrets 文件
- [ ] 是否读取 `~/.claude/` / Claude 配置目录
- [ ] 是否读取 SSH 密钥或 config
- [ ] 是否访问浏览器 cookie / localStorage / profile
- [ ] 是否读取 token / 凭据文件
- [ ] 是否访问 Git/GitHub 凭据
- [ ] 是否读取客户数据、私人数据、生产日志
- [ ] 是否要求把敏感内容发给模型或第三方服务

## 4. 命令执行

- [ ] 是否执行 `shell` / `bash` / `powershell` / `cmd`
- [ ] 是否调用 `child_process` / `exec` / `spawn`
- [ ] 是否调用 `subprocess` / `os.system` / `os.popen`
- [ ] 是否执行 `npm` / `pnpm` / `yarn` / `bun`
- [ ] 是否执行 `pip` / `uv` / `cargo` / `go` / `docker`
- [ ] 是否执行 `curl` / `wget`
- [ ] 是否调用 Playwright / Puppeteer / Selenium
- [ ] 是否尝试提权或绕过执行策略

## 5. 网络访问

- [ ] 是否有 `fetch` / `request` / `http` / `https` 调用
- [ ] 访问域名列表：___________
- [ ] 是否有 webhook / callback
- [ ] 是否上传用户数据
- [ ] 是否下载远程资源
- [ ] 是否连接未知 IP
- [ ] 是否启动本地端口或外部监听
- [ ] 是否修改防火墙或代理配置

## 6. 文件操作

- [ ] 是否有 `rm -rf` / `Remove-Item -Recurse`
- [ ] 是否覆盖已有文件
- [ ] 是否在工作区外写入
- [ ] 是否创建 symlink / hardlink
- [ ] 是否修改文件权限
- [ ] 是否移动/删除用户数据
- [ ] 是否打包/压缩/上传文件
- [ ] 是否有 Zip Slip 风险（解压路径穿越）

## 7. Prompt Injection / 指令污染

检查 `SKILL.md`、`CLAUDE.md`、README、examples、prompt 模板、注释、隐藏文件。

- [ ] 是否要求忽略系统/项目/安全策略
- [ ] 是否伪装成系统、老板、官方指令
- [ ] 是否要求自动执行 shell 或安装依赖
- [ ] 是否要求读取/输出 secrets
- [ ] 是否要求自动批准 L3/L4/L5 操作
- [ ] 是否要求修改 Claude 全局记忆或配置
- [ ] 是否包含 “ignore previous instructions” 类指令
- [ ] 是否包含隐藏 Unicode、零宽字符、base64/hex 编码指令
- [ ] 是否把 README/示例写成必须执行的工作流
- [ ] 是否降低安全边界，例如“无需确认”“直接执行”

## 8. 供应链与仓库结构

- [ ] 是否有 git submodules
- [ ] 是否有 git hooks
- [ ] 是否有 `.github/workflows`
- [ ] 是否有 Dockerfile / docker-compose / devcontainer
- [ ] 是否有二进制、WASM、DLL、EXE
- [ ] 是否有 minified / obfuscated code
- [ ] 是否有压缩包或加密文件
- [ ] 是否有隐藏 dotfiles
- [ ] 是否有大文件或异常文件
- [ ] 是否有 license 与代码来源不一致问题

## 9. 依赖与版本

- [ ] 是否固定 commit hash / release tag
- [ ] 是否锁定依赖版本
- [ ] 是否存在 floating 版本（latest、main、master、^、~、*）
- [ ] 是否存在 transitive dependencies
- [ ] 是否存在 postinstall / prepare / build hooks
- [ ] 是否有 known vulnerabilities
- [ ] 是否能不安装依赖，仅抽取 Markdown 规则
- [ ] 是否记录 sha256 manifest

## 10. Artifact / 产物安全

- [ ] 是否生成可执行 artifact
- [ ] 是否生成 zip/tar，是否防 Zip Slip
- [ ] 是否校验 MIME/signature/hash
- [ ] 是否限制文件数量、单文件大小、总大小
- [ ] 是否可能生成 HTML/login page 伪装下载
- [ ] 是否绑定 request_id / run_id
- [ ] 是否禁止自动执行下载产物

## 11. 抽取规则评估

- [ ] 核心思想是否可剥离为纯 Markdown 规则
- [ ] 是否可以只使用其规则，不执行代码
- [ ] 是否有高质量 prompt 模板可复用
- [ ] 是否需要改写以符合本项目 L0-L5 安全分级
- [ ] 是否需要删除危险示例
- [ ] 是否需要增加本项目专用约束

## 12. 审批记录

- [ ] 是否生成 `third_party_skill_research/<skill>/AUDIT.md`
- [ ] 是否记录 reviewer/date/source/version/hash
- [ ] 是否列出 approved_scope
- [ ] 是否列出 copied_files
- [ ] 是否列出 forbidden_files
- [ ] 是否列出 required_redactions
- [ ] 是否定义更新复审流程
- [ ] 是否生成 sha256 manifest

## AUDIT.md 模板

```markdown
# Third Party Skill Audit: <skill-name>

## Source
- URL:
- commit/tag:
- downloaded_at:
- reviewer:

## Verdict
- [ ] PASS
- [ ] REJECT
- [ ] CONDITIONAL PASS

## Scope
- approved_scope:
- copied_files:
- forbidden_files:
- required_redactions:

## Hash Manifest
| path | sha256 |
|---|---|

## Findings
| severity | item | evidence | decision |
|---|---|---|---|

## Decision
- 是否允许进入 skills/approved/：否/是，仅限改写后的纯 Markdown
- 是否允许执行脚本：否
- 是否需要 GPT-5.5 复核：是/否
- 下次更新是否需要重审：是
```

## 审计结论

- 结论：[ ] 通过 [ ] 不通过 [ ] 有条件通过
- P0/P1 是否清零：[ ] 是 [ ] 否
- 是否只复制纯 Markdown 规则：[ ] 是 [ ] 否
- 是否禁止整包复制：[ ] 是 [ ] 否
- 拒绝原因（如不通过）：___________
- 通过条件（如有保留）：___________
