# 统一事件日志 v2 — 加固版（锁 + 防覆盖 + 深度 + 校验）
param(
    [Parameter(Mandatory=$true)][string]$Type,
    [Parameter(Mandatory=$true)][bool]$Ok,
    [string]$DataJson = "{}"
)
$ErrorActionPreference = "Stop"

# Validate Type
if (-not $Type -or -not $Type.Trim()) { throw "Type is required" }

$EventLog = "D:\Code\ai-infra\logs\events.jsonl"

# Ensure log directory exists
$LogDir = Split-Path $EventLog -Parent
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Parse data, tolerate bad JSON
$data = try { $DataJson | ConvertFrom-Json } catch { [pscustomobject]@{ data_parse_error = $_.Exception.Message } }

# Build entry with reserved field protection
$entry = [ordered]@{
    ts = (Get-Date).ToUniversalTime().ToString("o")  # ISO 8601 UTC
    type = $Type
    ok = $Ok
}
$reserved = @("ts", "type", "ok")
if ($data) {
    foreach ($prop in $data.PSObject.Properties) {
        if ($reserved -contains $prop.Name) { continue }  # protect core fields
        $entry[$prop.Name] = $prop.Value
    }
}

# Write with file lock (concurrent-safe)
$json = $entry | ConvertTo-Json -Compress -Depth 10
$lockFile = "$EventLog.lock"
$lock = [System.IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None')
try {
    Add-Content -Path $EventLog -Value $json -Encoding UTF8
} finally {
    $lock.Close()
}
