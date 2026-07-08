---
tags: [network, deployment, firewall, lan, wifi]
match_keywords: [网络隔离, ping通TCP不通, WiFi有线不同网络, 端口不通, AP隔离, 防火墙规则多]
date: 2026-06-28
source: WiFi Win10部署后无法从Win11连接9000端口
severity: medium
status: final
---

# WiFi 和有线可能在同一子网但路由器隔离

## Symptom
- ping 192.168.1.19 通（2ms延迟）
- Test-NetConnection 192.168.1.19 -Port 9000 不通
- curl http://192.168.1.19:9000/health 超时
- 目标机器本地 curl http://127.0.0.1:9000/health 正常

## Trigger
- 两台机器在同一子网（192.168.1.x）
- 一台走有线（以太网），一台走WiFi
- 路由器启用AP隔离或不同VLAN

## Root Cause
路由器将WiFi和有线划分到不同广播域。ping使用ICMP可以跨VLAN，但TCP端口被隔离。防火墙规则只在目标机器本地生效，路由器层面的隔离优先级更高。

## Fix
1. 两台都连同一个网络（都WiFi或都有线）
2. 安装Tailscale组建VPN（推荐）
3. 路由器关闭AP隔离
4. USB/移动硬盘直接拷贝文件

## Prevention
- 部署前先 `Test-NetConnection <ip> -Port <port>` 验证连通性
- 不同网络 → 默认走Tailscale或物理介质
- 不要把TCP连通性假设为"IP通了端口就能通"
