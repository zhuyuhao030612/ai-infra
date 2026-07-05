# 敏感信息脱敏 —— 发给 GPT 前自动清洗
# 用法: "my text" | pwsh -File redact.ps1
#       pwsh -File redact.ps1 -Text "my text"
#       pwsh -File redact.ps1 -File "prompt.md"
param(
    [string]$Text = "",
    [string]$File = ""
)

function Redact-Text($inputText) {
    if (-not $inputText) { return $inputText }

    $result = $inputText

    # Token patterns (base64-like, 40+ chars)
    $result = $result -replace '([A-Za-z0-9_\-]{40,})', '[TOKEN_REDACTED]'

    # Common password patterns in context
    $result = $result -replace '(password|pass|pwd|token|secret|key)\s*[=:]\s*\S+', '$1=[REDACTED]'

    # IP addresses (keep private IPs for context, redact public)
    $result = $result -replace '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP_REDACTED]'

    # Email addresses
    $result = $result -replace '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', '[EMAIL_REDACTED]'

    # Port numbers in suspicious context
    $result = $result -replace ':\d{4,5}\b', ':[PORT_REDACTED]'

    # Windows product keys / license keys
    $result = $result -replace '\b[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}\b', '[LICENSE_KEY_REDACTED]'

    return $result
}

# Main
if ($File -and (Test-Path $File)) {
    $content = Get-Content $File -Raw -Encoding UTF8
    $redacted = Redact-Text $content
    $outPath = $File -replace '\.md$', '-redacted.md'
    $redacted | Out-File $outPath -Encoding UTF8
    Write-Host "[redact] $File → $outPath"
    Write-Host $redacted
} elseif ($Text) {
    Write-Host (Redact-Text $Text)
} else {
    # Pipeline mode
    $piped = $input | Out-String
    if ($piped.Trim()) {
        Write-Host (Redact-Text $piped)
    } else {
        Write-Host "用法: echo 'text with token abc123...' | pwsh -File redact.ps1"
        Write-Host "      pwsh -File redact.ps1 -Text 'text'"
        Write-Host "      pwsh -File redact.ps1 -File prompt.md"
    }
}
