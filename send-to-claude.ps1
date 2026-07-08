# 弹出输入框，支持中文输入法，内容发给 Claude Code
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "给 Claude 发消息（中文可输入）"
$form.Size = New-Object System.Drawing.Size(600, 300)
$form.StartPosition = "CenterScreen"
$form.Topmost = $true

$label = New-Object System.Windows.Forms.Label
$label.Text = "在下面打字，点「发送」或按 Ctrl+Enter："
$label.Location = New-Object System.Drawing.Point(15, 15)
$label.Size = New-Object System.Drawing.Size(560, 25)
$form.Controls.Add($label)

$textbox = New-Object System.Windows.Forms.TextBox
$textbox.Location = New-Object System.Drawing.Point(15, 45)
$textbox.Size = New-Object System.Drawing.Size(555, 140)
$textbox.Multiline = $true
$textbox.Font = New-Object System.Drawing.Font("Microsoft YaHei", 11)
$form.Controls.Add($textbox)

$button = New-Object System.Windows.Forms.Button
$button.Text = "发送"
$button.Location = New-Object System.Drawing.Point(240, 200)
$button.Size = New-Object System.Drawing.Size(100, 35)
$button.Add_Click({
    $text = $textbox.Text.Trim()
    if ($text) {
        $taskFile = "D:\Code\_claude_task.txt"
        $text | Out-File -FilePath $taskFile -Encoding UTF8
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    }
})
$form.Controls.Add($button)

$form.AcceptButton = $button
$form.ShowDialog() | Out-Null

$taskFile = "D:\Code\_claude_task.txt"
if (Test-Path $taskFile) {
    Write-Host ""
    Write-Host "===== 发送给 Claude: ====="
    $content = Get-Content $taskFile -Raw -Encoding UTF8
    Write-Host $content
    Write-Host "=========================="
    Write-Host ""
    # 启动 Claude 并发送
    $content | claude
}
