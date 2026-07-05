# Post-tool evidence recorder — captures every tool call into evidence.jsonl
# Wired as PostToolUse hook in .claude/settings.local.json
# Always exits 0 (never blocks), silent operation
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }

try {
    $data = $raw | ConvertFrom-Json
    $toolName = ($data.tool_name ?? $data.toolName ?? "unknown")
    $toolInput = $data.tool_input ?? $data.toolInput ?? @{}
    $toolOutput = $data.tool_output ?? $data.toolOutput ?? ""

    # Extract file paths from input (common patterns across tool types)
    $filePaths = @()
    if ($toolInput -is [string]) {
        # Try to find paths in string input
        $pathMatches = [regex]::Matches($toolInput, '(?:D:\\Code\\|D:/Code/)[^\s""'']+')
        $filePaths = $pathMatches | ForEach-Object { $_.Value -replace '/', '\' }
    } elseif ($toolInput -is [hashtable] -or $toolInput -is [PSCustomObject]) {
        $paths = @($toolInput.file_path, $toolInput.path, $toolInput.filePath, $toolInput.target)
        foreach ($p in $paths) {
            if ($p -and ($p -is [string]) -and $p.Trim()) {
                $filePaths += $p
            }
        }
    }

    # Generate input hash for dedup
    $inputStr = if ($toolInput -is [string]) { $toolInput } else { ($toolInput | ConvertTo-Json -Depth 3 -Compress) }
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($inputStr)
    )
    $inputHash = [BitConverter]::ToString($hash) -replace '-',''

    # Determine outcome
    $outcome = "success"
    if ($toolOutput -and ($toolOutput -is [string])) {
        if ($toolOutput -match 'error|Error|fail|Fail|exception|Exception|denied') {
            $outcome = "failure"
        }
    }

    # Find active run's evidence.jsonl
    $RootDir = if ($env:AI_ROOT) { $env:AI_ROOT } else { "D:\Code" }
    $runsDir = Join-Path $RootDir ".ai-state\runs"
    $evidencePath = $null

    if (Test-Path $runsDir) {
        $latest = Get-ChildItem $runsDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($latest) {
            $candidate = Join-Path $latest.FullName "evidence.jsonl"
            if (Test-Path $candidate) { $evidencePath = $candidate }
        }
    }

    if ($evidencePath) {
        $entry = @{
            ts = (Get-Date -Format "o")
            tool_name = $toolName
            input_hash = $inputHash.Substring(0, [Math]::Min(16, $inputHash.Length))
            outcome = $outcome
            file_paths = @($filePaths | Select-Object -Unique)
        } | ConvertTo-Json -Compress

        # Append atomically
        $lockFile = "$evidencePath.append.lock"
        $lock = [System.IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None')
        try {
            Add-Content -Path $evidencePath -Value $entry -Encoding UTF8
        } finally {
            $lock.Close()
        }
    }
} catch {
    # Silent — never fail, never block
} finally {
    exit 0
}
