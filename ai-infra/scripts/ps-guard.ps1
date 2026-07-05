# PowerShell 脚本安检 — 交付前必跑
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Path,[switch]$FailOnWarning)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$scriptPath=(Resolve-Path -LiteralPath $Path).Path
Write-Host "=== PS Guard: $scriptPath ==="
$errors=New-Object System.Collections.Generic.List[string]
$warnings=New-Object System.Collections.Generic.List[string]
function Err($m){$script:errors.Add($m)|Out-Null;Write-Host " ERROR: $m"}
function Warn($m){$script:warnings.Add($m)|Out-Null;Write-Host " WARN: $m"}

Write-Host '[1] Syntax...'
$tokens=$null;$parseErrors=$null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors)|Out-Null
if($parseErrors -and $parseErrors.Count){$parseErrors|ForEach-Object{Err $_.Message}}else{Write-Host ' OK'}

Write-Host '[2] Guardrails...'
$content=Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
if($content -notmatch 'Set-StrictMode\s+-Version\s+Latest'){Warn 'Missing Set-StrictMode -Version Latest'}
if($content -notmatch '\$ErrorActionPreference\s*=\s*["'']Stop["'']'){Warn 'Missing $ErrorActionPreference = Stop'}

Write-Host '[3] Risk scan...'
$rules=@(
 @{p='(?i)\bInvoke-Expression\b|\biex\b';s='E';m='Invoke-Expression/iex is not allowed'},
 @{p='(?i)\bStart-Process\b.*-Verb\s+RunAs';s='E';m='Elevation requires manual review'},
 @{p='(?i)\brisk_ack\s*=\s*\$?true\b';s='E';m='agent must not self-fill risk_ack=true'},
 @{p='"C:\\[^"]*"';s='E';m='Hardcoded C: path is not allowed'},
 @{p="''C:\\[^'']*''";s='E';m='Hardcoded C: path is not allowed'},
 @{p='(?i)(password|passwd|pwd|token|secret|api[_-]?key)\s*=';s='W';m='Possible secret assignment'},
 @{p='(?i)\$env:Path\s*\+?=';s='W';m='PATH modification detected'}
)
foreach($r in $rules){if($content -match $r.p){if($r.s -eq 'E'){Err $r.m}else{Warn $r.m}}}

Write-Host '[4] String/path scan...'
if($tokens){
 $tokens|Where-Object{$_.Kind -in @('StringExpandable','StringLiteral')}|ForEach-Object{
 $t=$_.Text
 if($t -match '(?i)(Bearer\s+[A-Za-z0-9._~+/=-]+|sk-[A-Za-z0-9_-]+|ghp_[A-Za-z0-9_]+)'){Err 'Possible credential literal'}
 if($t -match '[A-Z]:\\' -and $t -match 'C:\\'){Err "C: path-like string: $($t.Substring(0,[Math]::Min(80,$t.Length)))"}
 }
}
if($errors.Count){Write-Host "PS_GUARD_FAIL errors=$($errors.Count) warnings=$($warnings.Count)"; exit 1}
if($FailOnWarning -and $warnings.Count){Write-Host "PS_GUARD_FAIL warnings=$($warnings.Count)"; exit 2}
Write-Host "PS_GUARD_PASS warnings=$($warnings.Count)"
exit 0
