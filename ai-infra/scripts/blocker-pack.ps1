# 阻塞诊断包 — 同一方案失败两次后自动生成，问 GPT
param([Parameter(Mandatory=$true)][string]$Goal, [string]$Attempts = "")

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$dir = "D:\Code\.ai-state\blockers\$ts"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# Collect evidence
$pack = @"
# Blocker Pack: $Goal

**Time**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Goal
$Goal

## Attempts
$Attempts

## Current State
- Foreground window: $(try { Add-Type -Name B32 -Namespace API -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();' -ErrorAction Stop; $h = [API.B32]::GetForegroundWindow(); $sb = New-Object System.Text.StringBuilder(256); Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder t, int c);' -Name B33 -Namespace API; [API.B33]::GetWindowText($h,$sb,256); $sb.ToString() } catch { "unknown" })
- Active windows: $(try { Get-Process | Where-Object {$_.MainWindowTitle} | Select-Object -First 5 | ForEach-Object {"$($_.ProcessName): $($_.MainWindowTitle)"} | Out-String } catch { "N/A" })

## Next
Please suggest an alternative approach. Do NOT micro-adjust the current failing approach.
"@

$pack | Out-File "$dir\blocker-pack.md" -Encoding UTF8
Write-Host "Blocker pack: $dir\blocker-pack.md"
Write-Host "Send this to GPT-5.5 for alternative path"
