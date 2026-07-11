# A/B Benchmark: 12 项真实任务评估
# 每次跑完记录：成功率/耗时/是否绕圈/是否先定义成功判据/是否调用正确工具
$tasks = @(
    @{id="T01"; name="PowerShell 部署"; type="deploy"},
    @{id="T02"; name="Win10 环境探测"; type="deploy"},
    @{id="T03"; name="多文件 bugfix"; type="code"},
    @{id="T04"; name="GPT 管道修复"; type="gpt-pipeline"},
    @{id="T05"; name="GUI 裁剪+Vision+点击"; type="gui"},
    @{id="T06"; name="local-agent API 改动"; type="local-agent"},
    @{id="T07"; name="安全端点审查"; type="security"},
    @{id="T08"; name="cleanup 防误删"; type="code"},
    @{id="T09"; name="failure artifact 解释"; type="failure"},
    @{id="T10"; name="blocker 替代路径"; type="blocker"},
    @{id="T11"; name="context-pack 生成"; type="task"},
    @{id="T12"; name="final-report 生成"; type="task"}
)

$resultFile = "D:\Code\ai-infra\evals\benchmark-results.jsonl"
$runId = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "=== A/B Benchmark ==="
Write-Host "Run: $runId"
Write-Host "Tasks: $($tasks.Count)"
Write-Host ""

foreach ($t in $tasks) {
    Write-Host "--- $($t.id): $($t.name) ---"

    # Metrics to record
    $entry = [ordered]@{
        run_id = $runId
        task_id = $t.id
        task_name = $t.name
        task_type = $t.type
        timestamp = (Get-Date -Format "o")
        success = $null
        duration_sec = 0
        did_define_success_criteria = $false
        did_use_lessons_search = $false
        did_use_impact = $false
        did_use_ps_guard = $false
        did_use_gpt_review = $false
        did_use_blocker_pack = $false
        did_circle = $false
        attempts = 1
        notes = ""
    }

    $startTime = Get-Date
    Write-Host "  [ ] Define: Done when / Verify by / Fallback if"
    Write-Host "  [ ] Execute"
    Write-Host "  [ ] Verify"
    Write-Host "  [ ] Record"
    Write-Host ""
    Write-Host "  [MANUAL] Fill in results above, then press Enter to record..."
    Read-Host

    $entry.duration_sec = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    $entry | ConvertTo-Json -Compress | Add-Content -Path $resultFile -Encoding UTF8
}

Write-Host "=== Results: $resultFile ==="
Write-Host "Analyze: cat $resultFile | python -c '...'"
