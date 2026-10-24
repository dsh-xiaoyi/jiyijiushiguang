# 约定注入自检（改动 conventions 后跑这个）
# 目的：把"静默截断"变成"当场报警"。零副作用，只读。
$ErrorActionPreference = 'Continue'
$core = 'C:\dsh-mem\conventions.md'
$shardDir = 'C:\dsh-mem\conventions.d'
$plugin = 'C:\dsh-mem\dsh-memory-bridge\index.mjs'
$logDir = 'C:\dsh-mem\logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$log = Join-Path $logDir 'conventions-check.log'

function Say($m) { $l = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m; Add-Content $log $l -Encoding UTF8; Write-Host $l }

Say '=== conventions 注入自检 ==='
$fail = 0

# 1) 读插件里的上限（默认值 + 配置项）
$cap = 8000
$capSrc = '代码默认'
# 2026-10-24: 真正生效的是 bundle patch 里的 config（它覆盖代码默认），必须先读它
# 2026-10-24 采纳 18 的复核意见：不再硬编码 <USERPROFILE>（别的机器会 false PASS）
$cfgFiles = @('C:\dsh-mem\dsh-memory-bridge\cordis.patch.yml')
$prof = Join-Path $env:USERPROFILE '.dsh\profiles\desktop\cordis.patch.yml'
if (Test-Path -LiteralPath $prof) { $cfgFiles += $prof }
foreach ($cf in $cfgFiles) {
    if (-not (Test-Path $cf)) { continue }
    $cm = Select-String -Path $cf -Pattern '^\s*conventionsMax:\s*(\d+)' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cm) { $cap = [int]$cm.Matches[0].Groups[1].Value; $capSrc = ('生效配置 ' + $cf); break }
}
Say ('  注入上限 conventionsMax = ' + $cap + ' 字符（来源: ' + $capSrc + '）')

# 2) 核心文件
if (-not (Test-Path -LiteralPath $core)) {
    Say ('  FAIL 前提不成立：核心约定文件不存在 → ' + $core)
    Say '        （按 17/18 复核意见：检查器必须先自证前提，取不到目标就判 FAIL，不许跳过后算通过）'
    Say ('  RESULT: FAIL 1（前提不成立：核心文件缺失 -> ' + $core + '）')
    exit 1
}
$ct = [System.IO.File]::ReadAllText($core, [System.Text.Encoding]::UTF8)
$n = $ct.Length
$sections = ([regex]::Matches($ct, '(?m)^##\s.+$')).Count
if ($n -gt $cap) {
    $over = $n - $cap
    Say ('  FAIL 核心超限：' + $n + ' / ' + $cap + '（超出 ' + $over + ' 字符 ⇒ 尾部会被截断）')
    # 指出超限点之后会丢的章节
    $head = $ct.Substring(0, $cap)
    $rest = $ct.Substring($cap)
    $lost = ([regex]::Matches($rest, '(?m)^##\s.+$') | ForEach-Object { $_.Value.Trim() })
    if ($lost.Count -gt 0) { Say ('  会被截掉的章节： ' + ($lost -join ' ｜ ')) }
    $fail++
} else {
    Say ('  OK 核心 ' + $n + ' / ' + $cap + ' 字符，章节 ' + $sections + ' 个，剩余余量 ' + ($cap - $n))
}

# 3) BOM 与编码
$bytes = [System.IO.File]::ReadAllBytes($core)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
Say ('  核心 BOM=' + $hasBom + '（含中文的注入文件不要求 BOM，插件会剥掉）')

# 4) 分片
if (Test-Path $shardDir) {
    $fs = @(Get-ChildItem $shardDir -Filter '*.md')
    Say ('  分片数=' + $fs.Count)
    foreach ($f in $fs) {
        $bt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
        $first = ($bt -split "`r?`n")[0]
        $keys = @(([regex]::Matches($first, '\[([^\]]+)\]') | ForEach-Object { $_.Groups[1].Value -split '[,，\s]+' }) | Where-Object { $_ })
        if ($keys.Count -eq 0) { Say ('  FAIL 分片缺关键词行（第一行必须写成 [关键词1 关键词2]）: ' + $f.Name); $fail++ }
        else { Say ('    ' + $f.Name.PadRight(24) + $bt.Length.ToString().PadLeft(5) + ' 字符  关键词 ' + $keys.Count + ' 个') }
        if ($bt.Length -gt 1500) { Say ('  WARN 分片偏大（>1500 字符），命中时会挤占注入空间: ' + $f.Name) }
    }
} else {
    Say ('  WARN 分片目录不存在（不可核）: ' + $shardDir)
    Say '        若该机器本就该有分片，请当作 FAIL 处理；"没有目录"不等于"分片都合格"。'
}

# 5) 结论
if ($fail -eq 0) { Say '  RESULT: PASS（不会被静默截断）' } else { Say ('  RESULT: FAIL ' + $fail) }
Say '=== end ==='
exit $fail
