# 状态机定义 — 所有有状态实体

## 1. GPT Queue Request

```
created → queued(inbox) → processing → completed(outbox)
                                      → failed(failed/)
                                      → timeout(>120s in processing)
                                      → stale(>300s in processing → recovered)
```

**合法转换：** queued→processing, processing→completed|failed|timeout|stale
**幂等操作：** 同一 request_id 只处理一次
**stale 恢复：** processing > 5min → 移到 failed/ + 写 error response

## 2. Task Run

```
initialized → running → blocked → completed
                              → failed
```

**合法转换：** initialized→running, running→blocked|completed|failed, blocked→running|failed
**幂等操作：** 同一 run 不重复执行
**stale 恢复：** running > 24h → 标记为 abandoned

## 3. Failure Artifact

```
writing → complete → archived
```

**合法转换：** writing→complete, complete→archived
**幂等操作：** manifest.status 控制
**stale 恢复：** writing > 10min 无更新 → 标记为 partial

## 4. Lesson

```
draft → final → deprecated
```

**合法转换：** draft→final|deprecated, final→deprecated
**幂等操作：** status 字段控制
