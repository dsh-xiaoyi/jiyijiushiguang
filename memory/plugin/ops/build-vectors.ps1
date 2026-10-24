param(
    [string]$OllamaUrl = 'http://127.0.0.1:11434',
    [string]$Model = 'bge-m3',
    [string]$OutFile = 'C:\dsh-mem\mem-vectors.bin',
    [string]$ConfigPath = '',
    [int]$BodyChars = 800,
    [int]$Batch = 16,
    [int]$Limit = 0,
    [switch]$DryRun
)
# 2026-10-24 C4：用 18 上的 Ollama(bge-m3, 1024 维) 给记忆算向量，写成二进制缓存供插件做混合检索。
# 格式: magic 8B "DSHVEC01" | uint32 dim | uint32 count | int64 unixSeconds | count × (int64 id + dim×float32 LE)
$ErrorActionPreference = 'Stop'

# 2026-10-25 P2-b：跨会话互斥用**文件锁**（Local\ 只本会话有效；Global\ 需特权，非特权下构造会抛错）
#   文件锁天然跨会话/跨用户；锁文件内写 PID+时刻，>30 分钟视为陈旧
$lockPath = $OutFile + '.lock'
$lockStream = $null
try {
    $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $lockInfo = [System.Text.Encoding]::UTF8.GetBytes(([string]$PID + ' ' + (Get-Date).ToString('o') + ' ' + $env:USERNAME))
    $lockStream.Write($lockInfo, 0, $lockInfo.Length)
    $lockStream.Flush()
} catch {
    if ($lockStream) { try { $lockStream.Dispose() } catch { }; $lockStream = $null }
    $stale = $false
    if (Test-Path $lockPath) { $stale = ((Get-Item $lockPath).LastWriteTime -lt (Get-Date).AddMinutes(-30)) }
    if ($stale) {
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
        $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    } else {
        throw ('another build-vectors run is in progress (lock ' + $lockPath + ' held; delete it only if you are sure no build runs)')
    }
}

# 2026-10-25 P2-c：清理陈旧临时文件（>30 分钟），避免被误读成"有构建在进行"
Get-ChildItem -Path (Split-Path -Parent $OutFile) -Filter '*.tmp-*' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddMinutes(-30) } |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

try {
Add-Type -AssemblyName System.Data

# 2026-10-25 r7：路径参数化（18 在 G:\deepseek，硬编码 C:\dsh-mem 会直接失败）
if (-not $ConfigPath) {
    foreach ($c in @('C:\dsh-mem\dsh-mem.config.json','G:\deepseek\dsh-mem.config.json','E:\deepseek\dsh-mem.config.json')) {
        if (Test-Path $c) { $ConfigPath = $c; break }
    }
}
if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) { throw ('找不到 dsh-mem.config.json（试过 C:/G:/E:）; 请用 -ConfigPath 指定') }
Write-Output ('config: ' + $ConfigPath)
$cfg = ([System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
$cs = 'Server=' + $cfg.server + ';Database=' + $cfg.database + ';User Id=' + $cfg.user + ';Password=' + $cfg.password + ';TrustServerCertificate=True;Connect Timeout=20'
$c = New-Object System.Data.SqlClient.SqlConnection $cs
$c.Open()

# 2026-10-25 v4 修正：binStartDbCount 必须在**加载行之前**取
#   （v3 是在写完 bin 之后才查，若期间有新行入库，就会得到 start > bin 的"假 skipped"）
$binStartDbCount = 0
try {
    $q0 = $c.CreateCommand()
    $q0.CommandText = "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.memories WHERE ISNULL(status,'current') NOT IN ('retired','archived');"
    $binStartDbCount = [int]$q0.ExecuteScalar()
} catch {
    Write-Output ('WARN: binStartDbCount 查询失败，稍后按 rows.Count 兜底 (' + $_.Exception.Message + ')')
}

$sql = "SELECT TOP (" + $(if ($Limit -gt 0) { $Limit } else { 100000 }) + ") id, ISNULL(title,'') AS title, ISNULL(body,'') AS body FROM dbo.memories WHERE ISNULL(status,'current') NOT IN ('retired','archived') ORDER BY id"
$q = $c.CreateCommand(); $q.CommandText = $sql
$dt = New-Object System.Data.DataTable; $dt.Load($q.ExecuteReader()); $c.Close()
Write-Output ('memories to embed: ' + $dt.Rows.Count + '  (db live at start: ' + $binStartDbCount + ')')

$rows = @()
foreach ($r in $dt.Rows) {
    $txt = ([string]$r.title + "`n" + [string]$r.body)
    if ($txt.Length -gt $BodyChars) { $txt = $txt.Substring(0, $BodyChars) }
    $rows += [pscustomobject]@{ id = [int64]$r.id; text = $txt }
}
# 2026-10-25 v6：用**单调序（id）**做边界，不用时间戳
#   前提：id 单调递增（已在本库全表断言：倒序对=0、无重复、无 NULL created_at）
$maxIdAtLoad = 0; $minIdAtLoad = 0
if ($rows.Count -gt 0) {
    $maxIdAtLoad = ($rows | Measure-Object -Property id -Maximum).Maximum
    $minIdAtLoad = ($rows | Measure-Object -Property id -Minimum).Minimum
}
$rowCountAtLoad = $rows.Count
Write-Output ('id bounds at load: min=' + $minIdAtLoad + ' max=' + $maxIdAtLoad + ' rows=' + $rowCountAtLoad)
if ($DryRun) { Write-Output ('DRY: would embed ' + $rows.Count); exit 0 }

$vecs = New-Object 'System.Collections.Generic.List[object]'
$dim = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $rows.Count; $i += $Batch) {
    $slice = $rows[$i..([Math]::Min($i + $Batch - 1, $rows.Count - 1))]
    $payload = @{ model = $Model; input = @($slice | ForEach-Object { $_.text }) } | ConvertTo-Json -Depth 4 -Compress
    $tmpIn = Join-Path $env:TEMP ('emb-in-' + [guid]::NewGuid().ToString('N') + '.json')
    $tmpOut = Join-Path $env:TEMP ('emb-out-' + [guid]::NewGuid().ToString('N') + '.json')
    [System.IO.File]::WriteAllText($tmpIn, $payload, (New-Object System.Text.UTF8Encoding $false))
    $null = & cmd.exe /c ('curl.exe -s --max-time 120 -X POST "' + $OllamaUrl + '/api/embed" -H "Content-Type: application/json" --data-binary "@' + $tmpIn + '" -o "' + $tmpOut + '"')
    Remove-Item $tmpIn -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $tmpOut)) { throw ('embed failed at batch ' + $i) }
    $resp = ([System.IO.File]::ReadAllText($tmpOut, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
    Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
    if (-not $resp.embeddings) { throw ('no embeddings in response at batch ' + $i) }
    for ($k = 0; $k -lt $resp.embeddings.Count; $k++) {
        $v = $resp.embeddings[$k]
        if ($dim -eq 0) { $dim = $v.Count }
        $arr = New-Object 'single[]' $dim
        for ($d = 0; $d -lt $dim; $d++) { $arr[$d] = [single]$v[$d] }
        $vecs.Add([pscustomobject]@{ id = $slice[$k].id; vec = $arr })
    }
    if ((($i / $Batch) % 10) -eq 0) { Write-Output ('  embedded ' + $vecs.Count + ' / ' + $rows.Count + '  (' + [math]::Round($sw.Elapsed.TotalSeconds,1) + 's)') }
}
$sw.Stop()
Write-Output ('embedded total=' + $vecs.Count + ' dim=' + $dim + ' elapsed=' + [math]::Round($sw.Elapsed.TotalSeconds,1) + 's')

# ---- 写二进制 ----
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([System.Text.Encoding]::ASCII.GetBytes('DSHVEC01'))
$bw.Write([uint32]$dim)
$bw.Write([uint32]$vecs.Count)
$bw.Write([int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
foreach ($x in $vecs) {
    $bw.Write([int64]$x.id)
    $bytes = New-Object byte[] ($dim * 4)
    [System.Buffer]::BlockCopy($x.vec, 0, $bytes, 0, $bytes.Length)
    $bw.Write($bytes)
}
$bw.Flush()
$all = $ms.ToArray()
$bw.Close(); $ms.Close()
# 2026-10-25 原子写（P2）：先写同卷临时文件 → 校验 → 按固定顺序 rename（先 bin 后 meta）
#   理由：直写最终路径时若中途中断，会留下半个 .bin，读端只校验 magic ⇒ semantic 静默关闭
$OutDir  = Split-Path -Parent $OutFile
if (-not $OutDir) { $OutDir = '.' }
$tag     = 'tmp-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$tmpBin  = Join-Path $OutDir ([System.IO.Path]::GetFileName($OutFile) + '.' + $tag)
$metaPath = ($OutFile -replace '\.bin$', '.meta.json')
$tmpMeta = Join-Path $OutDir ([System.IO.Path]::GetFileName($metaPath) + '.' + $tag)

[System.IO.File]::WriteAllBytes($tmpBin, $all)

# 2026-10-25 sidecar：产物自带判据输入（离线可核）
#   ① 完整性：count + sha256 ⇒ 不需要库
#   ② 新鲜度：binStartDbCount / binEndDbCount ⇒ 把"构建后的实时尾"与"真落后"分开
# (binStartDbCount 已在加载行之前取到；此处不再重复查询)
$binEndDbCount = $binStartDbCount
try {
    $c2 = New-Object System.Data.SqlClient.SqlConnection $cs
    $c2.Open()
    $q2 = $c2.CreateCommand()
    $q2.CommandText = "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.memories WHERE ISNULL(status,'current') NOT IN ('retired','archived');"
    $binEndDbCount = [int]$q2.ExecuteScalar()
    $c2.Close()
} catch {
    Write-Output ('WARN: binEndDbCount query failed, keep ' + $binEndDbCount + ' (' + $_.Exception.Message + ')')
}
# 2026-10-25 v4：三段式拆分（不再让检查时用 binEnd-bin 去猜）
#   skipped = max(0, binStart - binCount)                    构建期漏掉的（行在库里但没进 bin）
#   tail    = max(0, binEnd - max(binCount, binStart))       构建完成后新增的（正常实时尾）
$limited = ($Limit -gt 0)
if ($limited) { $binSkipped = 0 } else { $binSkipped = [Math]::Max(0, $binStartDbCount - $vecs.Count) }
$binTail    = [Math]::Max(0, $binEndDbCount - [Math]::Max($vecs.Count, $binStartDbCount))
if ($vecs.Count -ne $rows.Count) {
    Write-Output ('WARN: embedded=' + $vecs.Count + ' but rows=' + $rows.Count + ' -> skipped=' + $binSkipped + ' (embed shortfall; check per-batch responses)')
}
Write-Output ('sidecar split: skipped=' + $binSkipped + ' tail=' + $binTail + ' (start=' + $binStartDbCount + ' end=' + $binEndDbCount + ' bin=' + $vecs.Count + ')')
$shaBin = (Get-FileHash -LiteralPath $tmpBin -Algorithm SHA256).Hash
Write-Output ('sidecar inputs: binStartDbCount=' + $binStartDbCount + ' binEndDbCount=' + $binEndDbCount + ' sha256=' + $shaBin.Substring(0,16))

$meta = [pscustomobject]@{
    model           = $Model
    dim             = $dim
    count           = $vecs.Count
    sha256          = $shaBin
    builtAt         = (Get-Date).ToString('o')
    generatedAt     = (Get-Date).ToString('o')
    binStartDbCount = $binStartDbCount
    binEndDbCount   = $binEndDbCount
    skipped         = $binSkipped
    maxIdAtLoad     = $maxIdAtLoad
    minIdAtLoad     = $minIdAtLoad
    rowCountAtLoad  = $rowCountAtLoad
    limited         = $limited
    tail            = $binTail
    bodyChars       = $BodyChars
    url             = $OllamaUrl
} | ConvertTo-Json
[System.IO.File]::WriteAllText($tmpMeta, $meta, (New-Object System.Text.UTF8Encoding $false))

# 校验临时产物：magic/dim/count 必须自洽，否则不替换
$chk = [System.IO.File]::ReadAllBytes($tmpBin)
$chkMagic = [System.Text.Encoding]::ASCII.GetString($chk[0..7])
$chkDim   = [BitConverter]::ToUInt32($chk, 8)
$chkCount = [BitConverter]::ToUInt32($chk, 12)
$chkCalc  = ($chk.Length - 24) / (8 + $dim * 4)
if ($chkMagic -ne 'DSHVEC01' -or $chkDim -ne $dim -or $chkCount -ne $vecs.Count -or $chkCalc -ne $vecs.Count) {
    Remove-Item $tmpBin, $tmpMeta -Force -ErrorAction SilentlyContinue
    throw ('temp verify failed: magic=' + $chkMagic + ' dim=' + $chkDim + ' count=' + $chkCount + ' calc=' + $chkCalc)
}

# 记录写入内容的 sha256（用于替换后逐字符比对，而不是只打印）
$shaWritten = (Get-FileHash -LiteralPath $tmpBin -Algorithm SHA256).Hash

# 固定顺序：先 bin，再 meta（顺序固定便于回滚判断）
Move-Item -LiteralPath $tmpBin -Destination $OutFile -Force
Move-Item -LiteralPath $tmpMeta -Destination $metaPath -Force

# 替换后重读最终文件再校验一次：**真做 sha256 比对**（不是只打印）
$fin = $null
try { $fin = [System.IO.File]::ReadAllBytes([string]$OutFile) } catch { $fin = $null }
if ($null -eq $fin -or $fin.Length -lt 24) { throw ('final verify failed: cannot read final file ' + $OutFile) }
$finCount = [BitConverter]::ToUInt32($fin, 12)
$finSha = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash
if ($finSha -ne $shaWritten) {
    throw ('final verify failed: sha256 mismatch (written=' + $shaWritten + ' ondisk=' + $finSha + ') — 疑似并发替换或落盘异常')
}
Write-Output ('wrote ' + $OutFile + '  ' + [math]::Round($fin.Length / 1MB, 2) + 'MB  count=' + $finCount + '  sha256=' + $finSha.Substring(0,16) + ' (atomic: temp+rename, sha verified)')
if ($finCount -ne $vecs.Count) { throw ('final verify failed: count=' + $finCount + ' expected=' + $vecs.Count) }
Write-Output ('meta -> ' + $metaPath)
} finally {
    if ($lockStream) { try { $lockStream.Dispose() } catch { }; $lockStream = $null }
    Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
}