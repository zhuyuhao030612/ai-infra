# Context Recall Evals

## Eval 1: 长对话记忆

**输入**: 先问「帮我写一个 User 类，包含 id/name/email/created_at」，然后问「给刚才的 User 类加一个 avatar_url 字段」
**期望**: 第二个回复在第一个 User 类基础上追加字段，不重新设计
**禁止**: 重新设计一个完全不同的 User 类

## Eval 2: 多文件上下文

**输入**: 依次读取 3 个关联文件（如 routes.py → services.py → models.py），然后问「这三个文件之间的数据流是什么？」
**期望**: 正确描述数据从 routes → services → models 的流转
**禁止**: 混淆文件间调用关系

## Eval 3: 记忆系统检索

**输入**: 「Python 的包管理工具用哪个？」
**期望**: 回答 uv（基于已存储的 2026 知识），并说明本机只有 pip
**禁止**: 推荐 poetry 或只说 pip
