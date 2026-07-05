# desktop-action.ps1 — desktop automation helper
param([ValidateSet("move","click","doubleclick","type","key","screenshot","wait")][string]$Action="screenshot",[int]$X=0,[int]$Y=0,[string]$Text="",[string]$Key="",[int]$DelayMs=300,[string]$RootDir=$(if($env:CLAUDE_PROJECT_DIR){$env:CLAUDE_PROJECT_DIR}else{"D:\Code"}))
Set-StrictMode -Version 2.0;$ErrorActionPreference="Continue"
function Get-Prop{param($o,$n,$d=$null)if($null-eq$o){return$d};$p=$o.PSObject.Properties[$n];if($null-eq$p){return$d};return$p.Value}
$RootDir=[IO.Path]::GetFullPath($RootDir)
$StateDir=Join-Path $RootDir ".claude\run-state";$ScreenshotDir=Join-Path $RootDir "screenshots"
New-Item -ItemType Directory -Force -Path $StateDir|Out-Null;New-Item -ItemType Directory -Force -Path $ScreenshotDir|Out-Null
Add-Type -AssemblyName System.Windows.Forms;Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class DAN{[DllImport("user32.dll")]public static extern bool SetCursorPos(int X,int Y);
[DllImport("user32.dll")]public static extern void mouse_event(uint dwFlags,uint dx,uint dy,uint dwData,UIntPtr dwExtraInfo);}
"@
$DOWN=0x0002;$UP=0x0004
function Click{param($cx,$cy)[DAN]::SetCursorPos($cx,$cy)|Out-Null;Start-Sleep -Milliseconds 80;[DAN]::mouse_event($DOWN,0,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 50;[DAN]::mouse_event($UP,0,0,0,[UIntPtr]::Zero)}
$result=[ordered]@{ok=$true;action=$Action;generated_at=(Get-Date -Format "o")}
try{switch($Action){
  "move"{[DAN]::SetCursorPos($X,$Y)|Out-Null}
  "click"{Click $X $Y}
  "doubleclick"{Click $X $Y;Start-Sleep -Milliseconds 100;Click $X $Y}
  "type"{[System.Windows.Forms.SendKeys]::SendWait($Text)}
  "key"{[System.Windows.Forms.SendKeys]::SendWait($Key)}
  "wait"{Start-Sleep -Milliseconds $DelayMs}
  "screenshot"{$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds;$bmp=New-Object System.Drawing.Bitmap($b.Width,$b.Height);$g=[System.Drawing.Graphics]::FromImage($bmp);try{$g.CopyFromScreen($b.X,$b.Y,0,0,$b.Size);$p=Join-Path $ScreenshotDir ("da-{0}.png" -f (Get-Date -Format "HHmmss"));$bmp.Save($p,[System.Drawing.Imaging.ImageFormat]::Png);$result.path=$p}finally{$g.Dispose();$bmp.Dispose()}}
}}catch{$result.ok=$false;$result.error=$_.Exception.Message}
$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $StateDir "desktop-action.json") -Encoding UTF8
Write-Output($result|ConvertTo-Json -Compress -Depth 6);exit $(if($result.ok){0}else{1})
