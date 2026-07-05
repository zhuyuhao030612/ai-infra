Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Activate {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
# Try multiple possible window titles
$titles = @("ToDesk", "Windows-J5M3P1", "ToDesk_")
$hwnd = [IntPtr]::Zero
foreach ($t in $titles) {
    $hwnd = [Win32Activate]::FindWindow($null, $t)
    if ($hwnd -ne [IntPtr]::Zero) { break }
}
# Fallback: find by process name
if ($hwnd -eq [IntPtr]::Zero) {
    $proc = Get-Process -Name "ToDesk" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne "" } | Select-Object -First 1
    if ($proc) { $hwnd = $proc.MainWindowHandle }
}
if ($hwnd) {
    [Win32Activate]::ShowWindow($hwnd, 9)  # SW_RESTORE
    [Win32Activate]::SetForegroundWindow($hwnd)
    Write-Host "ToDesk activated"
} else {
    Write-Host "ToDesk window not found"
}
