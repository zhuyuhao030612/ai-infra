# Register Windows Scheduled Tasks for all automation services
param([switch]$Remove)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$tasks = @(
  @{Name="AIAutomationWorker";Script="D:\Code\ai-infra\automation\automation-worker.ps1";Args="-Watchdog"}
  @{Name="GPT55ServerWatchdog";Script="D:\Code\ai-pipeline\scripts\gpt55-watchdog.ps1";Args=""}
)

foreach ($t in $tasks) {
  $taskName = $t.Name
  if ($Remove) {
    schtasks /delete /tn $taskName /f 2>$null
    Write-Host "Removed: $taskName"
  } else {
    $cmd = "pwsh -NoLogo -NoProfile -WindowStyle Hidden -File `"$($t.Script)`" $($t.Args)"
    schtasks /create /tn $taskName /tr $cmd /sc onstart /delay 0001:00 /f /rl LIMITED 2>$null
    # Start immediately
    schtasks /run /tn $taskName 2>$null
    Write-Host "Installed: $taskName"
  }
}
Write-Host "Done. Tasks will auto-start on boot with 1min delay."
