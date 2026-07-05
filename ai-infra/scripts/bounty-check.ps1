# bounty-check.ps1 — 每次会话开始跑，检查赚钱状态
param([switch]$Json)
$token = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN","User")
if(-not $token){ Write-Host "ERR: GITHUB_TOKEN not set"; exit 1 }
$headers = @{"Accept"="application/vnd.github.v3+json";"Authorization"="Bearer $token";"User-Agent"="bounty-checker"}

Write-Host "=== ACTIVE PRs ==="
# Add new PRs here as: @{Repo="owner/repo";Num=123}
$activePRs = @(@{Repo="cuentaprueba244w-dotcom/TentOfTrials";Num=68;Amount="$35"},@{Repo="cuentaprueba244w-dotcom/TentOfTrials";Num=69;Amount="$18"})
foreach($pr in $activePRs){
  $url = "https://api.github.com/repos/$($pr.Repo)/pulls/$($pr.Num)"
  try {
    $r = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 5
    $updated = [DateTime]::Parse($r.updated_at).ToLocalTime().ToString("MM-dd HH:mm")
    if($r.merged){ Write-Host "✅ $($pr.Amount) MERGED!" }
    else { Write-Host "⏳ $($pr.Amount) $($pr.Repo)#$($pr.Num): $($r.state) (updated $updated)" }
  } catch { Write-Host "❌ $($pr.Repo)#$($pr.Num): API error" }
}

Write-Host "`n=== NEW BOUNTIES (24h) ==="
$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$q = "label:bounty+is:open+is:issue+created:>$yesterday+comments:<10"
$uri = "https://api.github.com/search/issues?q=$q&sort=created&order=desc&per_page=10"
$new = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 5
$skip = @('SecureBanana','SPLURT','screeps','rustchain','crypto','token','nft','NFT','ETH','cocohub')
$fresh = @()
foreach($item in $new.items){
  $repo = $item.repository_url -replace '.*/repos/',''
  $skipMe = $false; foreach($s in $skip){ if($repo -match $s -or $item.title -match $s){ $skipMe=$true; break } }
  if($skipMe){ continue }
  $amount = ''; if($item.title -match '\$(\d+)'){ $amount = "$$($matches[1])" }
  $fresh += [pscustomobject]@{Amount=$amount;Repo=$repo;Title=$item.title.Substring(0,[Math]::Min(60,$item.title.Length))}
}
if($fresh.Count -eq 0){ Write-Host "  No good ones today" } else { $fresh | Format-Table Amount,Repo,Title -AutoSize -Wrap }
