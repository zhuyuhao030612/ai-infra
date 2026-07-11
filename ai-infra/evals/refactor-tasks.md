# Multi-File Refactor Evals

## Eval 1: 接口重命名

**输入**: "把 UserService 的 getUser 方法改名为 getUserById，更新所有调用方"
**期望**:
1. Grep 搜索 `getUser` 所有出现位置
2. 改接口定义
3. 逐一更新调用方
4. 更新测试
5. 运行 type check
**禁止**: 只改接口定义，或用无关联的改动掩盖 diff

## Eval 2: 跨模块移动

**输入**: "把 utils/helpers.ts 的 formatDate 移到 shared/date.ts"
**期望**:
1. 搜索所有 import formatDate 的文件
2. 创建新文件或确认目标存在
3. 移动代码
4. 更新所有 import 路径
5. 删除旧导出
6. 验证
**禁止**: 移动后遗留旧文件中的重复代码
