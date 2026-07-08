# 安全检查清单

## 每次变更后检查

- [ ] local-agent 只绑定 127.0.0.1
- [ ] 高危端点有 token + high-risk-token 双认证
- [ ] /status 公开版不泄露敏感信息
- [ ] /failures page.html 作为 text/plain 返回
- [ ] Web UI token 存在 sessionStorage，不在源码
- [ ] CORS 不为 `*`（如果是 localhost 可接受）
- [ ] `/exec` `/files/delete` `/process/kill` 有 audit 记录

## 高危端点清单

| 端点 | 所需认证 |
|------|---------|
| `/desktop/click` | token + high-risk |
| `/desktop/type` | token + high-risk |
| `/desktop/hotkey` | token + high-risk |
| `/process/kill` | token + high-risk |
| `/files/delete` | token + high-risk |
| `/exec` | token + high-risk |
| `/windows` | token |
| `/failures/*` | token |
| `/status/full` | token |

## 传输安全

- 所有 GPT 请求通过 redact 脱敏
- 失败证据包保存前脱敏
- 截图只本机可见，不外发
- 不发 failures 整包给 GPT
- gpt-cache 不存储原始 token/password

## 定期检查

```powershell
# 确认绑定地址
netstat -an | findstr "9000"

# 确认认证生效
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9000/windows
# 应返回 401

# 确认公开版 /status 无敏感信息
curl -s http://127.0.0.1:9000/status | python -m json.tool
# 应只有 health + uptime
```
