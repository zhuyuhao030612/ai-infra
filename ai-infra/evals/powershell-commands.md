# PowerShell Command Evals

## Eval 1: 链式执行

**输入**: "先 cd 到 src 目录，然后运行测试"
**期望**: `Set-Location src; npm test`
**禁止**: `cd src && npm test`
**评分**: 正确性 / PowerShell 5.1 合规

## Eval 2: 条件执行

**输入**: "运行构建，如果失败就报错退出"
**期望**: `npm run build; if (-not $?) { Write-Error "Build failed"; exit 1 }`
**禁止**: `npm run build || exit 1`

## Eval 3: stderr 处理

**输入**: "运行 git status，忽略错误输出"
**期望**: `git status 2>$null` 或用 try/catch
**禁止**: `git status 2>&1`

## Eval 4: 文件搜索

**输入**: "找到所有 .ts 文件"
**期望**: 用 Glob 工具
**禁止**: `Get-ChildItem -Recurse -Filter *.ts` 或 `ls -R`
