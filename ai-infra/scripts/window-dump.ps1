# P0-1 学习：进程/窗口/前台关系
# 用不同应用测试：notepad / calc / Doubao / ToDesk
param([string]$ProcessName = "notepad")

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public class WinDump {
    public delegate bool EW(IntPtr h, IntPtr l);
    [DllImport("user32")] public static extern bool EnumWindows(EW f, IntPtr l);
    [DllImport("user32")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32")] public static extern int GetWindowText(IntPtr h, StringBuilder t, int n);
    [DllImport("user32")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32")] public static extern uint GetWindowLong(IntPtr h, int i);
    public struct RECT { public int L,T,R,B; }
    public const uint GW_OWNER = 4; public const int GWL_STYLE = -16;
    public const uint WS_EX_TOOLWINDOW = 0x80;
    public const uint WS_EX_APPWINDOW = 0x40000;
    public const uint WS_POPUP = 0x80000000;
}
"@

$procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
if (-not $procs) { Write-Host "Process '$ProcessName' not found. Starting notepad..."; Start-Process notepad; Start-Sleep 2; $procs = Get-Process notepad }

Write-Host "=== Window Dump: $ProcessName ==="
Write-Host "Processes: $($procs.Count)"
Write-Host ""

foreach ($p in $procs) {
    $p.Refresh()
    Write-Host "PID=$($p.Id) MainTitle='$($p.MainWindowTitle)' MainHandle=$($p.MainWindowHandle)"
    if ($p.MainWindowTitle -eq '') { Write-Host "  ⚠️ MainWindowTitle 为空 — 可能是托盘/后台/无窗口进程" }
    if ($p.MainWindowHandle -eq [IntPtr]::Zero) { Write-Host "  ⚠️ MainWindowHandle 为 0 — Get-Process 找不到顶层窗口" }

    # Enumerate ALL windows for this PID
    $pid32 = [uint32]$p.Id
    $wins = [System.Collections.ArrayList]::new()
    $cb = [WinDump+EW]{ param($h,$l)
        $p2=0u; [WinDump]::GetWindowThreadProcessId($h,[ref]$p2)
        if ($p2 -eq $pid32) {
            $sb=New-Object Text.StringBuilder 512; [WinDump]::GetWindowText($h,$sb,512)
            $r=New-Object WinDump+RECT; [WinDump]::GetWindowRect($h,[ref]$r)
            $style = [WinDump]::GetWindowLong($h, -16)
            $owner = [WinDump]::GetWindow($h, 4)
            [void]$wins.Add(@{
                Hwnd=$h; Title=$sb.ToString(); Vis=[WinDump]::IsWindowVisible($h);
                Min=[WinDump]::IsIconic($h); X=$r.L; Y=$r.T; W=$r.R-$r.L; H=$r.B-$r.T;
                Area=($r.R-$r.L)*($r.B-$r.T); Owner=$owner;
                Style=('{0:X8}' -f $style)
            })
        }
        return $true
    }
    [WinDump]::EnumWindows($cb, [IntPtr]::Zero)
    Write-Host "  Windows found: $($wins.Count)"

    # Categorize
    $visible = $wins | Where-Object Vis
    $hidden = $wins | Where-Object { -not $_.Vis }
    $large = $visible | Where-Object { $_.W -gt 100 -and $_.H -gt 100 }
    $tiny = $visible | Where-Object { $_.W -le 100 -or $_.H -le 100 }
    $owned = $wins | Where-Object { $_.Owner -ne [IntPtr]::Zero }

    Write-Host "    Visible: $($visible.Count) (large=$($large.Count) tiny=$($tiny.Count))"
    Write-Host "    Hidden: $($hidden.Count)  Owned: $($owned.Count)"
    Write-Host "    MinWidth: 200"

    foreach ($w in ($wins | Sort-Object Area -Descending)) {
        $tags = @()
        if ($w.Vis) { $tags += "VIS" } else { $tags += "HID" }
        if ($w.Min) { $tags += "MIN" }
        if ($w.Area -gt 20000) { $tags += "LARGE" }
        if ($w.Owner -ne [IntPtr]::Zero) { $tags += "OWNED" }
        if ($w.Title -eq '' -and $w.Vis -and $w.Area -gt 20000) { $tags += "NONAME" }
        Write-Host "    $($tags -join '|') $($w.W)x$($w.H) '$($w.Title)' Style=$($w.Style)"
    }
    Write-Host ""
}

# Summary
$fg = [WinDump]::GetForegroundWindow()
$sb=New-Object Text.StringBuilder 512; [WinDump]::GetWindowText($fg,$sb,512)
Write-Host "Foreground: $fg '$($sb.ToString())'"
