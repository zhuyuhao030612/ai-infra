# bounty-scanner.ps1 v2 — smart filter: skip fake/crypto/flooded, rank real USD bounties
param([int]$TopN=20,[switch]$Json)
$ErrorActionPreference="Stop"
$token=[Environment]::GetEnvironmentVariable("GITHUB_TOKEN","User")
if(-not $token){Write-Host "ERR: GITHUB_TOKEN not set";exit 1}
$headers=@{"Authorization"="Bearer $token";"User-Agent"="bounty-scanner-v2";"Accept"="application/vnd.github.v3+json"}

# Broad search, we filter locally
$queries=@(
  "label:bounty+is:open+is:issue+language:python+created:>=2026-06-01"
  "label:bounty+is:open+is:issue+language:typescript+created:>=2026-06-01"
  "label:bounty+is:open+is:issue+language:javascript+created:>=2026-06-01"
)

$all=@()
foreach($q in $queries){
  try{
    $r=Invoke-RestMethod -Uri "https://api.github.com/search/issues?q=$q&sort=created&order=desc&per_page=30" -Headers $headers -TimeoutSec 15
    foreach($item in $r.items){$all+=$item}
    Start-Sleep -Milliseconds 500  # rate limit breathing room
  }catch{Write-Host "Search failed: $_"}
}

# Dedup
$seen=@{}
$all=@($all|Where-Object{!$seen[$_.html_url];$seen[$_.html_url]=$true})

# Scoring heuristics
$scored=@()
foreach($i in $all){
  $repo=$i.repository_url -replace '.*/repos/',''
  $title=$i.title
  $body=$i.body??""
  $fullText="$title $body".ToLower()
  $score=0

  # KILL: crypto/token/nft
  if($fullText -match '\b(crypto|token|nft|airdrop|solana|blockchain|web3)\b'){continue}
  if($repo -match '\b(crypto|token|nft|airdrop|sol|splurt|secure.?banana)\b'){continue}

  # KILL: test/sandbox repos
  if($repo -match 'test|sandbox|demo|example|dummy|fake|auto.?fork'){continue}

  # KILL: flooded (>20 comments = too late)
  if($i.comments -gt 20){continue}

  # SCORE: USD amount mentioned
  if($fullText -match '\$(\d+)'){$score+=[int]$Matches[1]/10}
  elseif($fullText -match '(\d+)\s*usd'){$score+=[int]$Matches[1]/10}

  # SCORE: real words in title (not just emoji/symbols)
  if($title -match '[a-zA-Z]{10,}'){$score+=5}

  # SCORE: detailed body (>200 chars)
  if($body.Length -gt 200){$score+=10}

  # SCORE: fresh but not too fresh (1-14 days)
  $days=(Get-Date)-([datetime]$i.created_at)
  if($days.TotalDays -le 14){$score+=5}
  if($days.TotalDays -le 3){$score+=3}

  # Fetch repo info for stars
  try{
    $repoInfo=Invoke-RestMethod -Uri "https://api.github.com/repos/$repo" -Headers $headers -TimeoutSec 5
    $stars=$repoInfo.stargazers_count
    $repoAge=(Get-Date)-([datetime]$repoInfo.created_at)
    if($stars -gt 100){$score+=15}
    elseif($stars -gt 10){$score+=8}
    elseif($stars -gt 0){$score+=3}
    if($repoAge.TotalDays -lt 30){$score-=10}  # penalty for brand new repos
  }catch{$score+=0}

  $scored+=[pscustomobject]@{
    Score=[math]::Round($score,0)
    Title=$title
    Repo=$repo
    USD=$(if($fullText -match '\$(\d+)'){ "`$"+$Matches[1] }else{"?"})
    Comments=$i.comments
    Created=[datetime]$i.created_at|Get-Date -Format "yyyy-MM-dd"
    URL=$i.html_url
  }
  Start-Sleep -Milliseconds 300
}

# Sort and output
$result=$scored|Sort-Object Score -Descending|Select-Object -First $TopN

if($Json){
  $result|ConvertTo-Json -Depth 3
}else{
  if($result.Count -eq 0){Write-Host "No real USD bounties found. Market is dry."}
  else{
    Write-Host "`n=== Top $($result.Count) Real Bounties ==="
    $result|Format-Table Score,USD,Title,Comments,Repo -AutoSize -Wrap
    Write-Host "`n`n=== URLs ==="
    $result|ForEach-Object{Write-Host "$($_.Score) | $($_.Title) | $($_.URL)"}
  }
}
