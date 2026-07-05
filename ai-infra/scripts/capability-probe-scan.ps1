<#
.SYNOPSIS
自动扫描 Claude Code 能力：脚本、Skills、Hooks、MCP 工具、Python 包、服务端口。
对比 CAPABILITY_REGISTRY.md，输出缺失项。
.USAGE
pwsh D:\Code\ai-infra\scripts\capability-probe-scan.ps1
pwsh D:\Code\ai-infra\scripts\capability-probe-scan.ps1 -WritePending
pwsh D:\Code\ai-infra\scripts\capability-probe-scan.ps1 -Json
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\Code",
    [string]$RegistryPath = "C:\Users\ZHUYU\.claude\projects\D--Code\CAPABILITY_REGISTRY.md",
    [string[]]$ScriptRoots = @("D:\Code\ai-infra\scripts", "D:\Code\ai-pipeline", "D:\Code"),
    [string[]]$SkillRoots = @("D:\Code\.claude\skills", "C:\Users\ZHUYU\.claude\skills"),
    [string[]]$HookRoots = @("D:\Code\ai-infra\hooks", "D:\Code\.claude\hooks"),
    [string[]]$SettingsCandidates = @("D:\Code\.claude\settings.local.json", "D:\Code\.claude\settings.json"),
    [switch]$WritePending,
    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Normalize-Name {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
    return ($Name.ToLowerInvariant() -replace '\.ps1$|\.py$|\.js$|\.ts$|\.cmd$|\.bat$', '' -replace '[^a-z0-9_\-:\.]', '')
}

function Read-TextSafe {
    param([string]$Path)
    try { if (Test-Path -LiteralPath $Path) { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 } } catch {}
    return ""
}

function Add-Item {
    param([System.Collections.Generic.List[object]]$List, [string]$Kind, [string]$Name, [string]$Path = "", [string]$Hint = "")
    $n = Normalize-Name $Name
    if (-not $n) { return }
    $List.Add([pscustomobject]@{kind=$Kind; name=$Name; norm=$n; path=$Path; hint=$Hint}) | Out-Null
}

function Test-Port {
    param([int]$Port)
    try {
        $client = New-Object Net.Sockets.TcpClient
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(250, $false)
        if ($ok -and $client.Connected) { $client.Close(); return $true }
        $client.Close()
    } catch {}
    return $false
}

$registryText = Read-TextSafe $RegistryPath
$registryLower = $registryText.ToLowerInvariant()
$found = [System.Collections.Generic.List[object]]::new()

# 1. 扫描脚本
foreach ($root in $ScriptRoots | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -File -Include *.ps1,*.py,*.js,*.ts,*.cmd,*.bat |
        Where-Object { $_.FullName -notmatch '\\node_modules\\|\.git\\|__pycache__\\|\.venv\\|venv\\' } |
        ForEach-Object { Add-Item -List $found -Kind "script" -Name $_.BaseName -Path $_.FullName -Hint "脚本" }
}

# 2. 扫描 Skills
foreach ($root in $SkillRoots | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -File -Filter "SKILL.md" | ForEach-Object {
        $skillName = Split-Path (Split-Path $_.FullName -Parent) -Leaf
        Add-Item -List $found -Kind "skill" -Name $skillName -Path $_.FullName -Hint "Skill"
    }
}

# 3. 扫描 Hooks
foreach ($root in $HookRoots | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -File -Include *.ps1,*.py,*.js,*.ts | ForEach-Object {
        Add-Item -List $found -Kind "hook" -Name $_.BaseName -Path $_.FullName -Hint "Hook"
    }
}

# 4. 扫描 settings 中的 Hook matcher / MCP server
foreach ($settings in $SettingsCandidates | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath $settings)) { continue }
    $txt = Read-TextSafe $settings
    if (-not $txt) { continue }
    try {
        $json = $txt | ConvertFrom-Json -Depth 50
        $txtMatches = [regex]::Matches($txt, '"matcher"\s*:\s*"([^"]+)"')
        foreach ($m in $txtMatches) { Add-Item -List $found -Kind "hook-matcher" -Name $m.Groups[1].Value -Path $settings -Hint "Hook matcher" }
        $cmdMatches = [regex]::Matches($txt, '"command"\s*:\s*"([^"]+)"')
        foreach ($m in $cmdMatches) {
            if ($m.Groups[1].Value -match '([A-Za-z0-9_\-]+)\.ps1') { Add-Item -List $found -Kind "hook-command" -Name $Matches[1] -Path $settings -Hint "Hook command" }
        }
        if ($json.PSObject.Properties.Name -contains "mcpServers") {
            foreach ($p in $json.mcpServers.PSObject.Properties) { Add-Item -List $found -Kind "mcp-server" -Name $p.Name -Path $settings -Hint "MCP server" }
        }
    } catch {}
}

# 5. 内置工具基线
$builtInTools = @("Agent","AskUserQuestion","Bash","CronCreate","CronDelete","CronList","DesignSync","Edit","EnterPlanMode","ExitPlanMode","EnterWorktree","ExitWorktree","Glob","Grep","Monitor","NotebookEdit","PowerShell","PushNotification","Read","ScheduleWakeup","SendMessage","Skill","TaskCreate","TaskGet","TaskList","TaskOutput","TaskStop","TaskUpdate","WebFetch","WebSearch","Workflow","Write")
$playwrightTools = @("browser_click","browser_close","browser_console_messages","browser_drag","browser_drop","browser_evaluate","browser_file_upload","browser_fill_form","browser_handle_dialog","browser_hover","browser_mouse_click_xy","browser_mouse_down","browser_mouse_drag_xy","browser_mouse_move_xy","browser_mouse_up","browser_mouse_wheel","browser_navigate","browser_navigate_back","browser_network_request","browser_network_requests","browser_press_key","browser_resize","browser_run_code_unsafe","browser_select_option","browser_snapshot","browser_tabs","browser_take_screenshot","browser_type","browser_wait_for")
$windowsMcpTools = @("automation_windows","automation_elements","automation_mouse","automation_keyboard","automation_visual","automation_assert","automation_dialog","automation_shortcut","automation_task","automation_system","automation_mission","automation_macro","automation_smart","automation_watch","automation_analyze","get_desktop_state","get_window_state","cua_computer_use_screenshot","automation_face","global_keylogger")

foreach ($t in $builtInTools) { Add-Item -List $found -Kind "builtin-tool" -Name $t -Hint "Claude Code builtin" }
foreach ($t in $playwrightTools) { Add-Item -List $found -Kind "playwright-tool" -Name $t -Hint "Playwright MCP" }
foreach ($t in $windowsMcpTools) { Add-Item -List $found -Kind "windows-mcp-tool" -Name $t -Hint "Windows Computer Use MCP" }

# 6. Python 包扫描
$pythonPackages = @("pyautogui","pywinauto","pygetwindow","pynput","keyboard","pytesseract","cv2","PIL","psutil","chromadb","mem0")
foreach ($pkg in $pythonPackages) {
    try { $result = (& py -3 -c "import importlib.util; print('OK' if importlib.util.find_spec('$pkg') else 'NO')" 2>$null) -join "" } catch { $result = "" }
    if ($result -eq "OK") { Add-Item -List $found -Kind "python-package" -Name $pkg -Hint "Python package installed" }
}

# 7. 服务端口
$ports = @(@{name="local-agent-9000"; port=9000}, @{name="agent-hub-9100"; port=9100}, @{name="ollama-11434"; port=11434})
foreach ($p in $ports) {
    if (Test-Port -Port $p.port) { Add-Item -List $found -Kind "service-port" -Name $p.name -Hint $p.name }
}

# 8. 去重
$unique = $found | Group-Object kind,norm | ForEach-Object { $_.Group | Select-Object -First 1 } | Sort-Object kind,name

# 9. 对比 registry
$missing = [System.Collections.Generic.List[object]]::new()
foreach ($item in $unique) {
    $present = $false
    if ($registryLower.Contains($item.norm) -or $registryLower.Contains($item.name.ToLowerInvariant())) { $present = $true }
    if (-not $present) { $missing.Add($item) | Out-Null }
}

$report = [pscustomobject]@{generated_at=(Get-Date).ToString("s"); project_root=$ProjectRoot; registry=$RegistryPath; total_found=$unique.Count; missing_count=$missing.Count; missing=$missing}

if ($Json) {
    $report | ConvertTo-Json -Depth 8
} else {
    Write-Host "Capability Probe Scan" -ForegroundColor Cyan
    Write-Host "Registry: $RegistryPath"
    Write-Host "Found: $($unique.Count), Missing from registry: $($missing.Count)"
    if ($missing.Count -gt 0) {
        Write-Host "`nMissing capability candidates:" -ForegroundColor Yellow
        foreach ($m in $missing) { Write-Host ("- [{0}] {1} :: {2}" -f $m.kind, $m.name, $m.path) }
    } else { Write-Host "`nNo obvious missing capabilities." -ForegroundColor Green }
}

if ($WritePending) {
    $pendingPath = Join-Path (Split-Path $RegistryPath -Parent) "CAPABILITY_REGISTRY.pending.md"
    $lines = @("# CAPABILITY_REGISTRY.pending.md","","自动扫描发现但未在 registry 中命中的能力候选。人工审核后合并。","")
    foreach ($m in $missing) { $lines += ("TRIGGER: {0} | USE: {1} | CALL: {1} | FALLBACK: manual" -f $m.name, $m.name) }
    New-Item -ItemType Directory -Force -Path (Split-Path $pendingPath -Parent) | Out-Null
    Set-Content -LiteralPath $pendingPath -Encoding UTF8 -Value ($lines -join [Environment]::NewLine)
    Write-Host "`nPending file written: $pendingPath" -ForegroundColor Cyan
}

if (-not $Json -and $missing.Count -gt 0) { exit 2 }
exit 0
