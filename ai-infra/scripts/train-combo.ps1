# 组合拳训练器 — 每次任务前过一遍肌肉记忆
param([string]$Combo = "all")

$combos = @{
    deploy = @(
        @{step="env-probe"; cmd="pwsh -File D:\Code\ai-infra\scripts\env-probe.ps1"; verify="輸出 OS/User/Admin/PS/PATH/tools"},
        @{step="ps-guard"; cmd="pwsh -File D:\Code\ai-infra\scripts\ps-guard.ps1 -Path <script>"; verify="PS_GUARD_PASS"},
        @{step="dry-run"; cmd="<script> -DryRun"; verify="只输出计划，不执行"},
        @{step="apply"; cmd="<script> -Apply"; verify="每步返回OK"},
        @{step="verify"; cmd="curl http://.../health"; verify="200 + status:ok"}
    )
    gui = @(
        @{step="gui-probe"; cmd="pwsh -File D:\Code\ai-infra\scripts\gui-probe.ps1"; verify="窗口标题+矩形+裁剪截图路径+KB"},
        @{step="crop-check"; cmd="确认截图<50KB"; verify="文件存在且<100KB"},
        @{step="vision"; cmd="node D:\Code\ai-pipeline\vision.js <crop.jpg> '<prompt>'"; verify="返回坐标或描述"},
        @{step="click"; cmd="换算绝对坐标→desktop/click"; verify="x,y在窗口范围内"},
        @{step="verify-change"; cmd="再gui-probe→对比hash"; verify="截图hash变化或窗口标题变化"}
    )
    blocker = @(
        @{step="stop"; cmd="停止当前方案"; verify="确认已停止"},
        @{step="blocker-pack"; cmd="pwsh -File D:\Code\ai-infra\scripts\blocker-pack.ps1 -Goal '...'"; verify="blocker-pack.md已生成"},
        @{step="ask-gpt"; cmd="发送blocker-pack到GPT-5.5"; verify="发送成功"},
        @{step="new-path"; cmd="按GPT建议切换方案"; verify="新方案不同于原方案"},
        @{step="boss-update"; cmd="pwsh -File D:\Code\ai-infra\scripts\boss-update.ps1"; verify="老板知道卡在哪"}
    )
}

Write-Host "=== Combo Training: $Combo ==="
Write-Host ""

if ($Combo -eq "all") { $keys = $combos.Keys } else { $keys = @($Combo) }

foreach ($k in $keys) {
    Write-Host "━━━ $k 组合拳 ━━━"
    $i = 1
    foreach ($s in $combos[$k]) {
        Write-Host "  $i. $($s.step)"
        Write-Host "     命令: $($s.cmd)"
        Write-Host "     验证: $($s.verify)"
        $i++
    }
    Write-Host ""
}

Write-Host "训练完成。记住：每拳必验证，无反馈不继续。"
