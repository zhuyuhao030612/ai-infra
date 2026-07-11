# Playbooks — 强制操作流程

## 1. Deploy Playbook（部署/环境配置）

```
1. env-probe.ps1          → 探测目标环境
2. ps-guard.ps1 script    → 语法+风险安检
3. script.ps1 -DryRun     → 试运行
4. script.ps1 -Apply      → 真实执行
5. verify                  → curl health / check process
```

**硬规则：** 没过 env-probe + ps-guard，不许部署。

## 2. GUI Playbook（桌面自动化）

```
1. gui-probe.ps1          → 窗口信息 + 裁剪截图 + UIA dump
2. vision.js crop.jpg     → 分析截图定位目标
3. click at coordinates   → 换算绝对坐标点击
4. gui-probe.ps1          → 再次探测验证状态变化
5. hash/title 对比        → 确认操作生效
```

**硬规则：** 没有截图裁剪/状态验证，同一 GUI 操作不许试第三次。

## 3. Blocker Playbook（遇到阻塞）

```
1. 同一方案失败 2 次     → 强制刹车
2. blocker-pack.ps1       → 打包证据
3. 发送 to GPT-5.5       → 问替代路径
4. 切换方案，不微调      → 不走原路
```

**硬规则：** 失败两次必须 blocker-pack + GPT，禁止继续微调原方案。

## 4. Code Change Playbook（代码修改）

```
1. new-run.ps1            → 建立运行目录
2. lessons-search.ps1     → 查历史坑
3. impact.ps1 (3+文件)    → 影响分析
4. 修改代码
5. ps-guard.ps1 (.ps1)    → PowerShell 安检
6. verify.ps1             → 项目验证
7. smoke/run-all.ps1      → 冒烟测试
8. close-run.ps1          → 收口
```
