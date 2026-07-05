Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct RECT { public int Left, Top, Right, Bottom; }
public class Win32Rect {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
"@
$titles = @("ToDesk", "Windows-J5M3P1")
$hwnd = [IntPtr]::Zero
foreach ($t in $titles) {
    $hwnd = [Win32Rect]::FindWindow($null, $t)
    if ($hwnd -ne [IntPtr]::Zero) { break }
}
if ($hwnd -eq [IntPtr]::Zero) {
    $proc = Get-Process -Name "ToDesk" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne "" } | Select-Object -First 1
    if ($proc) { $hwnd = $proc.MainWindowHandle }
}
$rect = New-Object RECT
[Win32Rect]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top
Write-Host "$($rect.Left),$($rect.Top),$w,$h"
