param(
    [string]$BinPath = 'C:\dsh-mem\mem-vectors.bin',
    [string]$ConfigPath = '',
    [int]$DbCount = -1,
    [double]$MaxMissingPct = 2.0,
    [int]$MaxMissingRows = 50,
    [switch]$IdDiff,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Continue'
# 2026-10-25 v5 canonical
#   判据 = 谓词 + 采样时机 + 数据源（三者缺一即 unverifiable）
#   1) integrity（离线，不需库）：count == sidecar.count / sha256 == disk / skipped == 0 / start <= bin
#   2) freshness（需库）：gap = skipped + tail@build + added-after-build（可加合，打印和）
#   3) limited=true => unverifiable(limited build)，绝不判 FRESH
#   判词自带 criteria=freshness@<self sha16>（与注入尾巴 injector=0.5.0-<build> 同构）

$SelfSha16 = 'UNKNOWN'
try { $SelfSha16 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.Substring(0,16) } catch { $SelfSha16 = 'UNKNOWN' }
if ($SelfSha16 -eq 'UNKNOWN' -or $SelfSha16 -notmatch '^[0-9A-F]{16}$') {
    Write-Host 'RESULT: FAIL 1 (self-hash unavailable -> criteria cannot be stated; 判词不可比，拒绝输出)'
    exit 1
}
$Criteria = 'freshness@' + $SelfSha16

function Get-BinCount([string]$p) {
    if (-not (Test-Path $p)) { return $null }
    $len = (Get-Item $p).Length
    $body = $len - 24
    $rec = 8 + 1024 * 4
    if ($body % $rec -ne 0) { return -1 }
    return [int]($body / $rec)
}

function Get-BinIds([string]$p, [int]$n) {
    $res = New-Object 'System.Collections.Generic.HashSet[Int64]'
    if (-not (Test-Path $p) -or $n -le 0) { return $res }
    $fs = [System.IO.File]::OpenRead($p)
    try {
        $fs.Position = 24
        $buf = New-Object byte[] 8
        $recLen = 8 + 1024 * 4
        for ($i = 0; $i -lt $n; $i++) {
            $fs.Read($buf, 0, 8) | Out-Null
            [void]$res.Add([BitConverter]::ToInt64($buf, 0))
            $fs.Position = $fs.Position + ($recLen - 8)
        }
    } finally { $fs.Dispose() }
    return $res
}

function Invoke-ScalarSql([string]$connStr, [string]$sql) {
    try {
        $c = New-Object System.Data.SqlClient.SqlConnection $connStr
        $c.Open()
        $q = $c.CreateCommand(); $q.CommandText = $sql
        $v = $q.ExecuteScalar()
        $c.Close()
        return $v
    } catch { return $null }
}

function Get-DbInfo() {
    if ($DbCount -ge 0) { return @{ live = $DbCount; source = 'arg'; conn = $null } }
    $sqlLive = "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.memories WHERE ISNULL(status,'current') NOT IN ('retired','archived');"
    $cands = @($ConfigPath, 'C:\dsh-mem\dsh-mem.config.json', 'G:\deepseek\dsh-mem.config.json', 'E:\deepseek\dsh-mem.config.json') | Where-Object { $_ -and (Test-Path $_) }
    foreach ($cp in $cands) {
        try {
            $cfg = ([System.IO.File]::ReadAllText($cp, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
            $cs = 'Server=' + $cfg.server + ';Database=' + $cfg.database + ';User Id=' + $cfg.user + ';Password=' + $cfg.password + ';TrustServerCertificate=True;Connect Timeout=15'
            $live = Invoke-ScalarSql $cs $sqlLive
            if ($null -ne $live) { return @{ live = [int]$live; source = ('config ' + $cp); conn = $cs } }
        } catch { }
    }
    $cs2 = 'Server=127.0.0.1;Database=DSHMemory;Integrated Security=True'
    $liveE = Invoke-ScalarSql $cs2 $sqlLive
    if ($null -ne $liveE) { return @{ live = [int]$liveE; source = 'integrated'; conn = $cs2 } }
    return $null
}

if ($SelfTest) {
    $bad = 0
    $cases = @(
        @{ name = 'normal';  len = 24 + 1790 * 4104; exp = 1790 },
        @{ name = 'corrupt'; len = 24 + 1790 * 4104 + 5; exp = -1 },
        @{ name = 'empty';   len = 24; exp = 0 }
    )
    foreach ($c in $cases) {
        $tmp = Join-Path $env:TEMP ('vec-' + [guid]::NewGuid().ToString('N') + '.bin')
        $fs = [System.IO.File]::Create($tmp); $fs.SetLength([int64]$c.len); $fs.Close()
        $got = Get-BinCount $tmp
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        if ($got -eq $c.exp) { Write-Host ('  PASS case(' + $c.name + ') -> ' + $got) }
        else { Write-Host ('  FAIL case(' + $c.name + ') expect=' + $c.exp + ' got=' + $got); $bad++ }
    }
    if ($bad -eq 0) { Write-Host ('SELFTEST: PASS (3/3)  criteria=' + $Criteria); exit 0 }
    Write-Host ('SELFTEST: FAIL ' + $bad); exit 1
}

$integrityFail = $false
$coverageFail = $false
$binN = Get-BinCount $BinPath
$metaPath = ($BinPath -replace '\.bin$', '.meta.json')
$sc = $null
if (Test-Path $metaPath) {
    try { $sc = ([System.IO.File]::ReadAllText($metaPath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json } catch { $sc = $null }
}

Write-Host ('=== 1) integrity (offline, no DB needed)   criteria=' + $Criteria + ' ===')
Write-Host ('  bin     : ' + $(if ($null -eq $binN) { 'missing' } elseif ($binN -lt 0) { 'corrupt' } else { "$binN" }) + '  (' + $BinPath + ')')
if ($null -eq $sc) {
    Write-Host '  sidecar : MISSING -> integrity unverifiable (rebuild with v5 to get count/sha256/start/end/skipped)'
} else {
    $scSha = [string]$sc.sha256
    $diskSha = (Get-FileHash -LiteralPath $BinPath -Algorithm SHA256).Hash
    $scShort = $(if ($scSha.Length -ge 16) { $scSha.Substring(0,16) } else { $scSha })
    Write-Host ('  sidecar : count=' + $sc.count + ' sha256=' + $scShort + ' start=' + $sc.binStartDbCount + ' end=' + $sc.binEndDbCount + ' skipped=' + $sc.skipped + ' limited=' + $sc.limited)
    $intOk = $true
    $c1 = ($null -ne $binN) -and ($binN -ge 0) -and ([int]$sc.count -eq $binN)
    if ($c1) { Write-Host ('  [1/4] PASS count_match      sidecar=' + $sc.count + ' bin=' + $binN) }
    else { Write-Host ('  [1/4] FAIL count_match      sidecar=' + $sc.count + ' bin=' + $binN); $intOk = $false }
    $c2 = ($scSha -eq $diskSha)
    if ($c2) { Write-Host ('  [2/4] PASS sha_match        sidecar=' + $scShort + ' disk=' + $diskSha.Substring(0,16)) }
    else { Write-Host ('  [2/4] FAIL sha_match        sidecar=' + $scShort + ' disk=' + $diskSha.Substring(0,16)); $intOk = $false }
    $sk0 = $(if ($null -ne $sc.skipped) { [int]$sc.skipped } else { -1 })
    if ($sk0 -eq 0) { Write-Host '  [3/4] PASS skipped_zero     skipped=0' }
    elseif ($sk0 -lt 0) { Write-Host '  [3/4] WARN skipped_unknown  sidecar has no skipped field (older build)'; $intOk = $false }
    else { Write-Host ('  [3/4] FAIL skipped_zero     skipped=' + $sk0 + ' (rows in DB but not in bin; 每条都要登记理由，否则视为 embed 失败)'); $intOk = $false }
    $startN = $(if ($null -ne $sc.binStartDbCount) { [int]$sc.binStartDbCount } else { -1 })
    $c4 = ($startN -ge 0) -and ($null -ne $binN) -and ($binN -ge 0) -and ($startN -le $binN)
    if ($c4) { Write-Host ('  [4/4] PASS start_le_bin     start=' + $startN + ' bin=' + $binN + ' => ' + $startN + ' <= ' + $binN + ' = True') }
    else { Write-Host ('  [4/4] FAIL start_le_bin     start=' + $startN + ' bin=' + $binN + ' => False' + $(if ($startN -gt 0 -and $binN -ge 0) { ' (缺 ' + ($startN - $binN) + ' 行且 skipped 未登记)' } else { '' })); $intOk = $false }
    if ($intOk) { Write-Host '  PASS integrity: 4/4 (count_match, sha_match, skipped_zero, start_le_bin)' } else { $integrityFail = $true }
    if (-not $IdDiff) { Write-Host '  (id coverage not checked; add -IdDiff to verify every pre-build row is present)' }
}

Write-Host ''
Write-Host '=== 2) freshness (needs DB; only this part needs it) ==='
if ($null -ne $sc -and ($sc.PSObject.Properties.Name -contains 'limited') -and $sc.limited) {
    Write-Host '  sidecar says limited=true (preview/limited build) -> this bin is intentionally incomplete'
    Write-Host ('RESULT: unverifiable(limited build) - 拒绝判 FRESH/STALE；请用完整构建重跑 criteria=' + $Criteria)
    exit 2
}

$db = Get-DbInfo
if ($null -eq $db) {
    Write-Host '  db      : unreachable (config / integrated / -DbCount all unavailable)'
    Write-Host ('RESULT: unverifiable (freshness precondition not met; integrity above still stands) criteria=' + $Criteria)
    exit 2
}
Write-Host ('  db      : ' + $db.live + ' live rows  (source=' + $db.source + ')')
if ($null -eq $binN) { Write-Host ('RESULT: unverifiable (bin missing) criteria=' + $Criteria); exit 2 }
if ($binN -lt 0) { Write-Host ('RESULT: FAIL 1 (bin corrupt) criteria=' + $Criteria); exit 1 }

$missing = $db.live - $binN
if ($missing -lt 0) { $missing = 0 }
$pct = if ($db.live -gt 0) { [math]::Round(($missing * 100.0) / $db.live, 2) } else { 0 }
Write-Host ('  gap     : ' + $missing + ' (' + $pct + '%)  threshold: >' + $MaxMissingPct + '% or >' + $MaxMissingRows)

$sk = 0; $tailAtBuild = 0
if ($null -ne $sc) {
    if ($null -ne $sc.skipped) { $sk = [int]$sc.skipped }
    if ($null -ne $sc.tail) { $tailAtBuild = [int]$sc.tail }
}
$afterBuild = $missing - $sk - $tailAtBuild
if ($afterBuild -lt 0) { $afterBuild = 0 }
$sum = $sk + $tailAtBuild + $afterBuild
$addOk = ($sum -eq $missing)
Write-Host ('  gap split: skipped=' + $sk + '  |  tail@build=' + $tailAtBuild + '  |  added-after-build=' + $afterBuild)
Write-Host ('             => gap ' + $missing + ' = ' + $sk + ' + ' + $tailAtBuild + ' + ' + $afterBuild + ' = ' + $sum + '  [additive check: ' + $(if ($addOk) { 'PASS' } else { 'FAIL (sum != gap)' }) + ']')

if ($IdDiff) {
    Write-Host ''
    Write-Host '=== 3) id coverage (-IdDiff) ==='
    if ($null -eq $db.conn) {
        Write-Host '  skipped: no DB connection available for id query'
    } else {
        # 2026-10-25 v6：用**单调序（id）**分类，不做时间比较
        #   前提已全表断言：id 升序时 created_at 不下降（倒序对 = 0）
        $binIds = Get-BinIds $BinPath $binN
        $c = New-Object System.Data.SqlClient.SqlConnection $db.conn
        $c.Open()
        # 0) 单调性断言（每次跑都核，成本=一条查询）
        $qm = $c.CreateCommand()
        $qm.CommandText = "SELECT COUNT(*) FROM (SELECT id, created_at, LAG(created_at) OVER (ORDER BY id) AS prev_ct FROM dbo.memories) t WHERE prev_ct IS NOT NULL AND created_at < prev_ct"
        $inv = [int]$qm.ExecuteScalar()
        Write-Host ('  monotonic assertion: inversions(id asc => created_at desc) = ' + $inv + $(if ($inv -eq 0) { '  PASS (id 可作单调边界)' } else { '  FAIL (id 不再单调；id 边界判据失效，退回时间比较)' }))
        # 1) 逐 id 覆盖
        $q = $c.CreateCommand()
        $q.CommandText = "SET NOCOUNT ON; SELECT id FROM dbo.memories WHERE ISNULL(status,'current') NOT IN ('retired','archived')"
        $rd = $q.ExecuteReader()
        $maxId = $(if ($null -ne $sc -and $null -ne $sc.maxIdAtLoad) { [int64]$sc.maxIdAtLoad } else { [int64]::MaxValue })
        $realLoss = New-Object System.Collections.Generic.List[int64]
        $tailIds = New-Object System.Collections.Generic.List[int64]
        $total = 0
        while ($rd.Read()) {
            $total++
            $id = [int64]$rd.GetValue(0)
            if (-not $binIds.Contains($id)) {
                if ($id -le $maxId) { $realLoss.Add($id) } else { $tailIds.Add($id) }
            }
        }
        $c.Close()
        Write-Host ('  coverage: db ids=' + $total + '  bin ids=' + $binIds.Count + '  maxIdAtLoad=' + $maxId + '  real-loss(id<=maxId)=' + $realLoss.Count + '  tail(id>maxId)=' + $tailIds.Count)
        if ($realLoss.Count -eq 0) { Write-Host '  PASS coverage: every row with id <= maxIdAtLoad is present in bin' }
        else { Write-Host ('  FAIL coverage: ' + $realLoss.Count + ' row(s) with id <= maxIdAtLoad are missing -> ' + (($realLoss | Select-Object -First 5) -join ',')); $coverageFail = $true }
        if ($tailIds.Count -gt 0) { Write-Host ('  info: ' + $tailIds.Count + ' row(s) added after load (id > maxIdAtLoad) — 正常尾巴') }
        if ($inv -ne 0) { Write-Host '  WARN monotonic assertion failed: id-based classification unreliable; 需人工确认'; $coverageFail = $true }

    }
}

if ($integrityFail) {
    Write-Host ('RESULT: FAIL 1 (integrity) criteria=' + $Criteria)
    exit 1
}
if ($coverageFail) {
    Write-Host ('RESULT: unverifiable(incomplete: coverage) criteria=' + $Criteria)
    Write-Host '  note: bin 本身没坏，但覆盖不全或单调前提失效 ⇒ 不判 FRESH/STALE'
    exit 2
}
if ($missing -gt $MaxMissingRows -or $pct -gt $MaxMissingPct) {
    Write-Host ('RESULT: STALE (rebuild suggested; vector is a point-in-time snapshot) criteria=' + $Criteria)
    exit 0
}
Write-Host ('RESULT: FRESH criteria=' + $Criteria)
exit 0
