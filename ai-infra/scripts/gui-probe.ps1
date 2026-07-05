# GUI 探测 — 自动化操作前必跑：窗口信息 + 裁剪截图 + 状态摘要
param([string]$WindowTitle = "")

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient

# 1. Find target window
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = if ($WindowTitle) {
    New-Object System.Windows.Automation.PropertyCondition @([System.Windows.Automation.AutomationElement]::NameProperty, $WindowTitle)
} else {
    [System.Windows.Automation.Condition]::TrueCondition
}
# Simpler: just get foreground window via Win32
Add-Type @"
using System; using System.Runtime.InteropServices;
public class GProbe {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$hwnd = [GProbe]::GetForegroundWindow()
$rect = New-Object GProbe+RECT
[GProbe]::GetWindowRect($hwnd, [ref]$rect)
$sb = New-Object System.Text.StringBuilder(256)
[GProbe]::GetWindowText($hwnd, $sb, 256)
$title = $sb.ToString()

$x = $rect.Left; $y = $rect.Top
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top

Write-Host "=== GUI Probe ==="
Write-Host "Title: $title"
Write-Host "Rect: X=$x Y=$y W=$w H=$h"

# 2. Cropped screenshot
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$cropPath = "D:\Code\screenshots\gui-probe-$([DateTime]::Now.ToString('HHmmss')).jpg"
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$params = New-Object System.Drawing.Imaging.EncoderParameters(1)
$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 40L)
$bmp.Save($cropPath, $codec, $params)
$bmp.Dispose()
$sizeKB = [Math]::Round((Get-Item $cropPath).Length / 1KB, 1)
Write-Host "Crop: $cropPath (${sizeKB}KB)"

# 3. UIA dump (brief)
Write-Host "UIA controls:"
try {
    $window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if (-not $window) { $pc = New-Object System.Windows.Automation.PropertyCondition @([System.Windows.Automation.AutomationElement]::NameProperty, $title); $window = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $pc) }
    if ($window) {
        $controls = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($c in $controls) {
            $t = $c.Current.ControlType.ProgrammaticName -replace '.*\.'
            $n = $c.Current.Name
            if ($n -and $t -match 'Button|Edit|ComboBox|CheckBox|Radio|Tab|Hyperlink|MenuItem') {
                Write-Host "  [$t] '$n'"
            }
        }
    } else { Write-Host "  (UIA window not found)" }
} catch { Write-Host "  (UIA failed)" }

Write-Host "PROBE_DONE"
Write-Host "Use vision.js with: $cropPath"
