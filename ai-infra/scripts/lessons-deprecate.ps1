# 将 lesson 标记为废弃
# 用法: pwsh -File lessons-deprecate.ps1 -Id "L001" -Reason "不再适用"
param(
    [Parameter(Mandatory=$true)][string]$Id,
    [string]$Reason = ""
)
$ErrorActionPreference = "Stop"
$LessonsDir = "D:\Code\ai-infra\data\lessons"
$file = Get-ChildItem "$LessonsDir\$Id-*.md" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $file) { Write-Host "Lesson $Id not found"; exit 1 }

$content = Get-Content $file.FullName -Raw -Encoding UTF8
$content = $content -replace 'status:\s*\w+', 'status: deprecated'
if ($Reason) {
    if ($content -match 'deprecated_reason:') {
        $content = $content -replace 'deprecated_reason:.*', "deprecated_reason: $Reason"
    } else {
        $content = $content -replace '(status: deprecated)', "`$1`ndeprecated_reason: $Reason"
    }
}
$content | Out-File $file.FullName -Encoding UTF8

# Update index
$indexFile = "$LessonsDir\index.json"
$index = Get-Content $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $index) {
    if ($entry.id -eq $Id) { $entry.status = "deprecated"; break }
}
$index | ConvertTo-Json -Depth 3 | Out-File $indexFile -Encoding UTF8

Write-Host "[deprecate] $Id → deprecated $(if($Reason){'— '+$Reason})"
