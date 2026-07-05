# memory-fts5.ps1 — FTS5 全文搜索记忆（Hermes 偷师补完）
# 跨会话记忆检索，比 Grep MEMORY.md 更智能
param(
  [Parameter(Mandatory=$true)][string]$Query,
  [int]$Limit = 10,
  [switch]$Json,
  [switch]$Rebuild
)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$MemDir = Join-Path (Join-Path $Root '..') 'memory'
$DbPath = Join-Path (Join-Path $Root 'runtime') 'memory-fts5.db'
$utf8 = New-Object System.Text.UTF8Encoding $false

# ── Build/Rebuild index ──
function Build-Index {
  Write-Host "[fts5] Building index..."
  # Use Python for SQLite FTS5 (PowerShell's SQLite support is limited)
  $script = @"
import sqlite3, os, glob, re
db = sqlite3.connect(r'$DbPath')
db.execute('CREATE VIRTUAL TABLE IF NOT EXISTS memories USING fts5(name, description, content, tokenize=unicode61)')
db.execute('DELETE FROM memories')

pattern = r'^---\s*\n(.*?)\n---\s*\n(.*)'
for f in sorted(glob.glob(r'$MemDir\*.md')):
    name = os.path.splitext(os.path.basename(f))[0]
    try:
        text = open(f, encoding='utf-8').read()
        m = re.match(pattern, text, re.DOTALL)
        content = text
        desc = ''
        if m:
            fm = m.group(1)
            content = m.group(2).strip()
            dm = re.search(r'description:\s*(.*)', fm)
            if dm: desc = dm.group(1)
        db.execute('INSERT INTO memories(name, description, content) VALUES(?,?,?)',
                   (name, desc, content))
    except Exception as e:
        print(f'ERROR {f}: {e}')
db.commit()
db.close()
print('OK')
"@
  $script | python - 2>&1 | Select-Object -Last 1
}

if ($Rebuild -or -not (Test-Path $DbPath)) {
  Build-Index
}

# ── Search ──
$searchScript = @"
import sqlite3, json, sys
db = sqlite3.connect(r'$DbPath')
q = ' '.join(sys.argv[1:]) if len(sys.argv) > 1 else ''
if not q:
    json.dump([], sys.stdout)
    db.close()
    sys.exit(0)

# FTS5 query with snippet
try:
    rows = db.execute(
        'SELECT name, description, snippet(memories, 2, char(8230), char(8230), '', 64) as ctx FROM memories WHERE memories MATCH ? ORDER BY rank LIMIT ?',
        (q, $Limit)
    ).fetchall()
except Exception:
    # Fallback to LIKE search
    like_q = '%' + q.replace("'", "''") + '%'
    rows = db.execute(
        'SELECT name, description, substr(content,1,200) as ctx FROM memories WHERE name LIKE ? OR description LIKE ? OR content LIKE ? LIMIT ?',
        (like_q, like_q, like_q, $Limit)
    ).fetchall()

results = [{'name': r[0], 'description': r[1] or '', 'context': r[2] or ''} for r in rows]
json.dump(results, sys.stdout, ensure_ascii=False)
db.close()
"@

$results = & python -c $searchScript $Query 2>$null | ConvertFrom-Json

if ($Json) {
  $results | ConvertTo-Json -Compress
} else {
  Write-Host "`n=== FTS5 Search: '$Query' ==="
  if ($results.Count -eq 0) {
    Write-Host "  No matches."
  } else {
    foreach ($r in $results) {
      Write-Host "`n  [$($r.name)] $($r.description)"
      Write-Host "  $($r.context)"
    }
  }
}
