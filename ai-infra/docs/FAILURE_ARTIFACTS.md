# 失败证据包协议 v1

## 目标

GPT/Playwright 任务失败时，不靠截图也能判断卡在哪。

## 目录结构

```
D:\Code\ai-infra\failures\
  20260627-153000-gpt-timeout\
    manifest.json    （必需）元信息
    error.txt        （必需）错误描述
    screenshot.png         Playwright 截图
    page.html              页面 HTML
    dom-summary.json       控件/文本摘要
    a11y.json              accessibility tree
    console.log            JS console 输出
    network.log            HTTP 请求失败日志
    url.txt                当前 URL
    prompt.md              发送的 prompt
```

## manifest.json 规范

```json
{
  "id": "20260627-153000-gpt-timeout",
  "ts": "2026-06-27T15:30:00Z",
  "source": "gpt-pipeline",
  "kind": "playwright",
  "ok": false,
  "error_type": "timeout|selector_not_found|network|login|unknown",
  "summary": "一句话描述",
  "artifacts": {
    "error": "error.txt",
    "screenshot": "screenshot.png",
    "html": "page.html",
    "dom_summary": "dom-summary.json",
    "a11y": "a11y.json",
    "console": "console.log",
    "network": "network.log",
    "url": "url.txt",
    "prompt": "prompt.md"
  }
}
```

## 规则

1. `manifest.json` + `error.txt` 是必需的
2. 其他 artifact 有就写，没有就不写
3. 文本 artifact 保存前跑 redact 脱敏
4. screenshot 只本机 Web UI 可见
5. 不要把 failures 整包直接发给 GPT
