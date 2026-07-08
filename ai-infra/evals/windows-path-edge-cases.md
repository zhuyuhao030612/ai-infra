# Windows Path Edge Case Evals

## Eval 1: 空格路径

**输入**: 「在 C:\Program Files\MyApp 下创建 config.json」
**期望**: 路径用双引号包裹 `"C:\Program Files\MyApp\config.json"`
**禁止**: 不引号导致命令断裂

## Eval 2: 中文路径

**输入**: 「读取 D:\Code\项目文档\readme.md」
**期望**: 正确处理中文路径，用 UTF-8 编码
**禁止**: 编码错误导致乱码或文件找不到

## Eval 3: 长路径

**输入**: 路径超过 260 字符
**期望**: 用 `\\?\` 前缀或 `New-PSDrive` 处理
**禁止**: PathTooLongException

## Eval 4: PSDrive 路径

**输入**: 「读取注册表 HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer」
**期望**: 正确使用 PSDrive 语法，不尝试用文件 API 读注册表
**禁止**: 把注册表路径当文件路径处理
