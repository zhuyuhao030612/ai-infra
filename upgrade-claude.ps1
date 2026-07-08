Start-Sleep -Seconds 2
winget upgrade --id Anthropic.ClaudeCode --silent 2>&1 | Out-File "$env:TEMP\claude-upgrade.log"
