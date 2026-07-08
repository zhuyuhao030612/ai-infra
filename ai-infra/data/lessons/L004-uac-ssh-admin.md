---
tags: [windows, ssh, uac, admin, security, deployment]
match_keywords: [UAC剥夺管理员令牌, SSH网络登录, 拒绝访问注册表, 计划任务权限, WMI绕过UAC, LocalAccountTokenFilterPolicy]
date: 2026-06-28
source: Win10 RDP启用尝试（reg add/netsh/sc config全被拒）
severity: high
status: final
---

# UAC 剥夺 SSH 网络登录的管理员令牌

## Symptom
- SSH用户明明在Administrators组
- `reg add HKLM\...` → 拒绝访问
- `Set-Service` → 拒绝访问
- `netsh advfirewall` → 拒绝访问
- `schtasks /create` → 拒绝访问

## Trigger
- 通过SSH网络登录（非本地交互登录）
- UAC的`LocalAccountTokenFilterPolicy`默认过滤管理员令牌
- 只有本地登录/RDP才获得完整管理员令牌

## Root Cause
Windows UAC对网络登录（SSH）剥离管理员令牌。用户属于Administrators组但进程运行在过滤后的标准令牌下。注册表/服务/防火墙操作需要完整管理员权限。

## Fix
1. WMI `process call create` 可能绕过部分限制
2. 计划任务以SYSTEM账户运行（如可创建）
3. 最佳：本地登录/RDP后操作
4. 或将 `LocalAccountTokenFilterPolicy` 设为1（需首次本地管理员操作）

## Prevention
- SSH不能替代RDP做系统配置
- 部署前先 env-probe 确认当前权限级别
- 需要管理员操作时明确告知老板
