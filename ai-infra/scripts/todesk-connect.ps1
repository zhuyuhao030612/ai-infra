# ToDesk 自动化连接 — UIAutomation 精确控件操作
param([string]$DeviceCode = "887292091", [string]$Password = "Aarons")

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

$root = [System.Windows.Automation.AutomationElement]::RootElement
$treeScope = [System.Windows.Automation.TreeScope]::Descendants

# Find ToDesk window
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, "ToDesk")
$todeskWin = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)

if (-not $todeskWin) {
    Write-Host "ToDesk not found via UIA"
    exit 1
}
$todeskWin.SetFocus()
Write-Host "ToDesk focused"

# List all Edit and Button controls for debugging
$editCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)

$edits = $todeskWin.FindAll($treeScope, $editCond)
$buttons = $todeskWin.FindAll($treeScope, $btnCond)

Write-Host "=== Input fields ==="
foreach ($e in $edits) {
    Write-Host "  name='$($e.Current.Name)' autoId='$($e.Current.AutomationId)' value='$($e.Current.ItemStatus)'"
}

Write-Host "=== Buttons ==="
foreach ($b in $buttons) {
    Write-Host "  name='$($b.Current.Name)' autoId='$($b.Current.AutomationId)'"
}

# Find the device code input (first Edit with no/little value)
$deviceInput = $null
foreach ($e in $edits) {
    try {
        $vp = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        Write-Host "  Input value: '$($vp.Current.Value)'"
        if ($vp.Current.Value.Length -lt 20) {
            $deviceInput = $e
            break
        }
    } catch {}
}

if ($deviceInput) {
    Write-Host "[Step] Setting device code: $DeviceCode"
    $deviceInput.SetFocus()
    Start-Sleep 0.2
    $vp = $deviceInput.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $vp.SetValue($DeviceCode)
    Write-Host "  Device code set"
} else {
    Write-Host "[Fallback] Using SendKeys"
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Start-Sleep 0.1
    [System.Windows.Forms.SendKeys]::SendWait($DeviceCode)
}

# Find connect button by name
$connectBtn = $null
foreach ($b in $buttons) {
    if ($b.Current.Name -match "连接") {
        $connectBtn = $b
        break
    }
}

if ($connectBtn) {
    Write-Host "[Step] Clicking connect button"
    try {
        $invoke = $connectBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invoke.Invoke()
    } catch {
        [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
        Start-Sleep 0.2
        [System.Windows.Forms.SendKeys]::SendWait(" ")
    }
    Write-Host "  Connected"
} else {
    Write-Host "[Fallback] Tab+Space"
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep 0.2
    [System.Windows.Forms.SendKeys]::SendWait(" ")
}

# Wait for password dialog
Start-Sleep 3

# Try to find password field
$pwRoot = [System.Windows.Automation.AutomationElement]::RootElement
$pwEdits = $pwRoot.FindAll($treeScope, $editCond)
$pwInput = $null
foreach ($e in $pwEdits) {
    try {
        $vp = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if ($vp.Current.IsReadOnly -eq $false -and $vp.Current.Value.Length -eq 0) {
            $pwInput = $e
            break
        }
    } catch {}
}

if ($pwInput) {
    Write-Host "[Step] Setting password via UIA"
    $pwInput.SetFocus()
    $vp = $pwInput.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $vp.SetValue($Password)
} else {
    Write-Host "[Step] Password via SendKeys"
    [System.Windows.Forms.SendKeys]::SendWait($Password)
}

Start-Sleep 0.3
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Write-Host "[Done] ToDesk connection flow completed"
