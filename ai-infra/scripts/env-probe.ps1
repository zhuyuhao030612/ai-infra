# 环境探测 — 部署前必跑
param([string]$RootDir=$(if($env:AI_ROOT){$env:AI_ROOT}else{'D:\Code'}),[string]$TargetDir='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$RootDir=[IO.Path]::GetFullPath($RootDir)
if(!$TargetDir){$TargetDir=Join-Path $RootDir 'local-agent'}
$TargetDir=[IO.Path]::GetFullPath($TargetDir)
Write-Host '=== Env Probe ==='
Write-Host "OS: $([Environment]::OSVersion.VersionString)"
Write-Host "User: $env:USERNAME"
$p=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
Write-Host "Admin: $(if($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){'YES'}else{'NO'})"
Write-Host "PSVersion: $($PSVersionTable.PSVersion)"
Write-Host "ExecutionPolicy: $(Get-ExecutionPolicy -Scope Process) (Process) / $(Get-ExecutionPolicy -Scope CurrentUser) (User) / $(Get-ExecutionPolicy -Scope LocalMachine) (Machine)"
$parts=@(); if($env:Path){$parts=$env:Path.Split(';')|Where-Object{$_}}
$n=[Math]::Min(3,$parts.Count)
Write-Host ($(if($n){'PATH preview: '+($parts[0..($n-1)] -join ';')+'...'}else{'PATH preview: EMPTY'}))
Write-Host ''
foreach($t in @('python','python3','py','node','npm','uv','git','pwsh','powershell','tar','curl')){
 $cmd=Get-Command $t -EA SilentlyContinue
 Write-Host (' {0,-12}: {1}' -f $t, $(if($cmd){$cmd.Source}else{'NOT FOUND'}))
}
Write-Host "`nDisks:"
Get-PSDrive -PSProvider FileSystem|Where-Object{$_.Free -gt 0}|Sort-Object Name|ForEach-Object{Write-Host (' {0}: Free={1}GB Root={2}' -f $_.Name,[Math]::Round($_.Free/1GB,1),$_.Root)}
Write-Host ''
Write-Host ($(if(Test-Path $TargetDir){"Target dir: $TargetDir EXISTS"}else{"Target dir: $TargetDir NOT FOUND"}))
$probeDir=Join-Path $RootDir '.probe-temp'; $probeFile=Join-Path $probeDir ('env-test-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
try{New-Item -ItemType Directory -Force -Path $probeDir|Out-Null;Set-Content $probeFile 'ok' -Encoding UTF8 -NoNewline;Remove-Item $probeFile -Force;Write-Host "Root write: OK ($probeDir)"}catch{Write-Host "Root write: FAILED ($($_.Exception.Message))"}
