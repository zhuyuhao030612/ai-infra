# local-agent watchdog — keeps the server alive
param([ValidateRange(1,65535)][int]$Port=9000,[ValidateSet('127.0.0.1','localhost')][string]$HostAddr='127.0.0.1',[ValidateRange(5,3600)][int]$CheckIntervalSec=30,[ValidateRange(1,20)][int]$FailureThreshold=2,[ValidateRange(1024,104857600)][int]$MaxLogBytes=10485760)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ScriptDir=Split-Path -Parent $PSCommandPath
$StartScript=Join-Path $ScriptDir 'start.ps1'; if(!(Test-Path $StartScript)){throw "start.ps1 not found: $StartScript"}
$HealthUrl="http://${HostAddr}:${Port}/health"; $LogFile=Join-Path $ScriptDir '..\logs\watchdog.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogFile)|Out-Null
function RotateLog{if(Test-Path $LogFile){$i=Get-Item $LogFile;if($i.Length -gt $MaxLogBytes){Move-Item $LogFile "$LogFile.$(Get-Date -Format yyyyMMdd-HHmmss)" -Force}}}
function Log($m){RotateLog;$line="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m";Write-Host $line;Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8}
function Get-AgentProcesses{$ep=[regex]::Escape([string]$Port);Get-CimInstance Win32_Process -EA SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -match 'uvicorn' -and $_.CommandLine -match 'app\.main:app' -and $_.CommandLine -match "--port\s+$ep"}}
function Restart-Agent($n){
 Log "RESTART #$n — launching $StartScript"
 $stale=@(Get-AgentProcesses)
 foreach($p in $stale){try{Log "Stopping stale local-agent PID $($p.ProcessId)";Stop-Process -Id $p.ProcessId -Force -EA Stop}catch{Log "Failed to stop PID $($p.ProcessId): $($_.Exception.Message)"}}
 if($stale.Count){Start-Sleep -Seconds 2}
 $args=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$StartScript,'-Port',[string]$Port,'-HostAddr',$HostAddr)
 $proc=Start-Process -FilePath 'pwsh' -ArgumentList $args -WindowStyle Hidden -PassThru
 Log "New instance launched PID $($proc.Id), waiting..."; Start-Sleep -Seconds 5
}
Log "Watchdog started. Watching ${HealthUrl} every ${CheckIntervalSec}s"
$restarts=0;$fails=0
while($true){
 try{$r=Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 3;if($r.StatusCode -eq 200){if($fails -gt 0){Log "Health OK (recovered after $fails failures)"};$fails=0}else{$fails++;Log "Health returned $($r.StatusCode) (failure #$fails)"}}catch{$fails++;Log "Health check failed: $($_.Exception.Message) (failure #$fails)"}
 if($fails -ge $FailureThreshold){$restarts++;Restart-Agent $restarts;$fails=0}
 Start-Sleep -Seconds $CheckIntervalSec
}
