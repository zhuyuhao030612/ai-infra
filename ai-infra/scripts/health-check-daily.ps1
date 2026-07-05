# health-check-daily.ps1 -- 每日AI基础设施健康检查 (GPT-5.5编写, DeepSeek审计通过)
param([string]$HealthRoot="D:\Code\ai-infra\health",[int]$DiskWarn=80,[int]$MemWarn=80,[int]$Port=9000,[switch]$NoNotify)
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
if(!(Test-Path $HealthRoot)){New-Item -ItemType Directory $HealthRoot -Force|Out-Null}
$dateName=Get-Date -Format "yyyy-MM-dd"
$reportPath=Join-Path $HealthRoot "$dateName.json"
$logPath=Join-Path $HealthRoot "health.log"
function Send-Notify{param($t,$m)
 if($NoNotify){return}
 try{Add-Type -AssemblyName System.Windows.Forms;Add-Type -AssemblyName System.Drawing
  $notify=New-Object System.Windows.Forms.NotifyIcon;$notify.Icon=[System.Drawing.SystemIcons]::Warning
  $notify.BalloonTipTitle=$t;$notify.BalloonTipText=$m;$notify.Visible=$true
  $notify.ShowBalloonTip(5000);Start-Sleep 6;$notify.Dispose()}catch{}}
function Test-TcpPort{param($h,[int]$p,[int]$t=2000)
 $c=New-Object System.Net.Sockets.TcpClient;try{$a=$c.BeginConnect($h,$p,$null,$null)
  if(!$a.AsyncWaitHandle.WaitOne($t,$false)){return $false};$c.EndConnect($a);return $true}catch{return $false}finally{$c.Close()}}
$checks=@()
# Disk
foreach($d in @("C:","D:")){$disk=Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"|?{$_.DeviceID -eq $d}|Select -First 1
 if(!$disk){$checks+=@{name="disk_$d";status="warning";message="未找到磁盘";data=@{drive=$d}};continue}
 $p=[math]::Round(($disk.Size-$disk.FreeSpace)/$disk.Size*100,1)
 $s=if($p -ge $DiskWarn){"warning"}else{"ok"}
 $checks+=@{name="disk_$d";status=$s;message="使用率 ${p}%";data=@{drive=$d;size_gb=[math]::Round($disk.Size/1GB,2);free_gb=[math]::Round($disk.FreeSpace/1GB,2);used_pct=$p}}}
# Memory
$os=Get-CimInstance Win32_OperatingSystem;$tp=[double]$os.TotalVisibleMemorySize;$fp=[double]$os.FreePhysicalMemory
$mp=[math]::Round(($tp-$fp)/$tp*100,1)
$ms=if($mp -ge $MemWarn){"warning"}else{"ok"}
$checks+=@{name="memory";status=$ms;message="使用率 ${mp}%";data=@{total_gb=[math]::Round($tp/1MB,2);free_gb=[math]::Round($fp/1MB,2);used_pct=$mp}}
# Processes
$procs=@()
foreach($n in @("claude","node","python","uv")){$c=@(Get-Process -Name $n -ErrorAction SilentlyContinue);$procs+=@{name=$n;count=$c.Count}}
$missing=$procs|?{$_.count -eq 0}
$checks+=@{name="core_processes";status=if($missing){"warning"}else{"ok"};message="核心进程";data=@{processes=$procs;missing=@($missing|% name)}}
# Port
$open=Test-TcpPort "127.0.0.1" $Port
$checks+=@{name="local_agent";status=if($open){"ok"}else{"critical"};message="端口$Port";data=@{port=$Port;open=$open}}
# GPU
try{$gpuOut=& nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>&1
 if($LASTEXITCODE -eq 0){$gpuParts=$gpuOut -split ",\s*"
  $checks+=@{name="gpu";status="ok";message="GPU正常";data=@{name=$gpuParts[0];util=$gpuParts[1];mem_used=$gpuParts[2];mem_total=$gpuParts[3];temp=$gpuParts[4]}}}
 else{$checks+=@{name="gpu";status="warning";message="nvidia-smi失败"}}}catch{$checks+=@{name="gpu";status="warning";message="GPU检查异常"}}
# Docker
try{$dv=& docker version --format "{{.Server.Version}}" 2>$null
 if($LASTEXITCODE -eq 0){$checks+=@{name="docker";status="ok";message="Docker运行中";data=@{version=$dv}}}
 else{$checks+=@{name="docker";status="warning";message="Docker未运行";data=@{installed=$true;running=$false}}}
}catch{$checks+=@{name="docker";status="warning";message="Docker未安装"}}
# Overall
$overall="ok"
if(@($checks|?{$_.status -eq "critical"}).Count -gt 0){$overall="critical"}
elseif(@($checks|?{$_.status -eq "warning"}).Count -gt 0){$overall="warning"}
$report=@{timestamp=(Get-Date -Format "o");host=$env:COMPUTERNAME;overall=$overall;checks=$checks}
$report|ConvertTo-Json -Depth 8|Set-Content $reportPath -Encoding UTF8
$line="[{0}] overall={1}" -f (Get-Date -Format "s"),$overall;Add-Content $logPath $line -Encoding UTF8
if($overall -ne "ok"){$bad=($checks|?{$_.status -ne "ok"}|% name) -join ",";Send-Notify "健康检查:$overall" "异常:$bad"}
Write-Host $line
exit $(if($overall -eq "critical"){2}elseif($overall -eq "warning"){1}else{0})
