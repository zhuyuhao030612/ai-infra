# 将 draft lesson 提升为 final
# 用法: pwsh -File lessons-promote.ps1 -Id "L002"
param(
    [Parameter(Mandatory=$true)][string]$Id
)
$ErrorActionPreference = "Stop"
$LessonsDir = "D:\Code\ai-infra\data\lessons"
$file = Get-ChildItem "$LessonsDir\$Id-*.md" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $file) { Write-Host "Lesson $Id not found"; exit 1 }

$content = Get-Content $file.FullName -Raw -Encoding UTF8
if ($content -notmatch 'status:\s*draft') {
    Write-Host "$Id is not draft (current: $(if($content -match 'status:\s*(\w+)'){$Matches[1]}))"
    exit 1
}
$content = $content -replace 'status:\s*draft', 'status: final'
$content | Out-File $file.FullName -Encoding UTF8

# Update index
$indexFile = "$LessonsDir\index.json"
$index = Get-Content $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $index) {
    if ($entry.id -eq $Id) { $entry.status = "final"; break }
}
$index | ConvertTo-Json -Depth 3 | Out-File $indexFile -Encoding UTF8

Write-Host "[promote] $Id → final"
