# 改动影响分析
param([string]$Files='',[string]$Symbol='',[string]$ProjectDir=$(if($env:AI_ROOT){$env:AI_ROOT}else{'D:\Code'}),[int]$MaxResults=30)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProjectDir=[IO.Path]::GetFullPath($ProjectDir)
if(!(Test-Path $ProjectDir)){throw "ProjectDir not found: $ProjectDir"}
if([string]::IsNullOrWhiteSpace($Files)){Write-Host '用法: pwsh -File impact.ps1 -Files "app/a.py,app/b.py" [-Symbol "verify_token"]'; exit 0}
$MaxResults=[Math]::Max(1,[Math]::Min($MaxResults,200))
$fileList=$Files -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_}|Select-Object -Unique
$skip='\\(node_modules|\.venv|venv|__pycache__|\.git|dist|build|\.mypy_cache|\.ruff_cache)\\'
$ext=@('*.py','*.js','*.ts','*.ps1','*.json','*.md')
function Rel($p){$f=[IO.Path]::GetFullPath($p); if($f.StartsWith($ProjectDir,[StringComparison]::OrdinalIgnoreCase)){return $f.Substring($ProjectDir.Length).TrimStart('\','/')} return $f}
$search=@(Get-ChildItem -LiteralPath $ProjectDir -Recurse -File -Include $ext -EA SilentlyContinue|Where-Object{$_.FullName -notmatch $skip})
Write-Host "=== 影响分析 ===`nProjectDir: $ProjectDir`n"
foreach($file in $fileList){
 $base=[IO.Path]::GetFileNameWithoutExtension((Split-Path $file -Leaf))
 $safe=[regex]::Escape(($base -replace '_','.'))
 Write-Host ">>> $file"
 Write-Host ' [imports]'
 $imports=@($search|Select-String -Pattern "from\s+.*$safe|import\s+.*$safe|require\s*\(.*$safe" -EA SilentlyContinue|Select-Object -First $MaxResults)
 if($imports.Count){$imports|ForEach-Object{Write-Host (' {0}:{1} : {2}' -f (Rel $_.Path),$_.LineNumber,$_.Line.Trim())}}else{Write-Host ' (无外部引用)'}
 if(![string]::IsNullOrWhiteSpace($Symbol)){
 Write-Host " [symbol: $Symbol]"
 $ss=[regex]::Escape($Symbol)
 $res=@($search|Select-String -Pattern "(?<![A-Za-z0-9_])$ss(?![A-Za-z0-9_])" -EA SilentlyContinue|Select-Object -First $MaxResults)
 if($res.Count){$res|ForEach-Object{Write-Host (' {0}:{1} : {2}' -f (Rel $_.Path),$_.LineNumber,$_.Line.Trim())}}else{Write-Host ' (未找到引用)'}
 }
 Write-Host ''
}
Write-Host '=== 分析完成 ==='
Write-Host '提示: 改前确认所有引用点都已考虑'
