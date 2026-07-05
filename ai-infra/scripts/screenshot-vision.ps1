# PHS Vision — screenshot + Doubao analysis
param([string]$Prompt = "Describe this screenshot. Focus on UI text, buttons, errors, and what the user should do next.", [int]$X = 0, [int]$Y = 0, [int]$W = 0, [int]$H = 0)

$ErrorActionPreference = "Stop"
$imgPath = Join-Path $env:TEMP "phs_vision_$(Get-Date -Format 'HHmmss').png"
$visionJS = "D:\Code\ai-pipeline\vision.js"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($W -eq 0) { $W = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width }
if ($H -eq 0) { $H = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height }

$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($X, $Y, 0, 0, [System.Drawing.Size]::new($W, $H))
$bmp.Save($imgPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

$result = & node $visionJS $imgPath $Prompt 2>&1
Write-Output $result
Remove-Item $imgPath -Force -ErrorAction SilentlyContinue
