# selftest.ps1 —— 一键自检（洁净机器演练用）
#
# 只做"读 + 一条可清理的写入"，不改系统设置、不装任何东西。
# 每一步打印 PASS / FAIL / SKIP，最后给 RESULT。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\ops\selftest.ps1
#   powershell -ExecutionPolicy Bypass -File .\ops\selftest.ps1 -ConfigPath C:\dsh-mem\dsh-mem.config.json
param(
    [string]$ConfigPath = 'C:\dsh-mem\dsh-mem.config.json',
    [string]$RepoRoot   = $(if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { '.' })
)
$ErrorActionPreference = 'Continue'
$fail = 0; $pass = 0; $skip = 0
# 让引擎（子进程）也读到同一份配置
$env:DSH_MEM_CONFIG = $ConfigPath
function Ok($m)   { Write-Output ('[PASS] ' + $m); $script:pass++ }
function Bad($m)  { Write-Output ('[FAIL] ' + $m); $script:fail++ }
function Skp($m)  { Write-Output ('[SKIP] ' + $m); $script:skip++ }

Write-Output ('== 记忆旧时光 selftest · ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Output ('   仓库: ' + $RepoRoot)
Write-Output ''

# 1) 仓库结构
Write-Output '--- A) 仓库结构'
foreach ($rel in @('README.md', 'memory\dsh-mem.ps1', 'memory\plugin\index.mjs', 'sql\sqlserver', 'ops\doctor.ps1')) {
    $p = Join-Path $RepoRoot $rel
    if (Test-Path $p) { Ok ('存在: ' + $rel) } else { Bad ('缺失: ' + $rel) }
}

# 2) 前置依赖
Write-Output '--- B) 前置依赖'
if (Get-Command sqlcmd -ErrorAction SilentlyContinue) { Ok 'sqlcmd 可用' } else { Bad 'sqlcmd 不可用（装 SQL Server 或 ODBC 驱动时会带）' }
if (Get-Command node -ErrorAction SilentlyContinue) { Ok ('node 可用: ' + (& node --version 2>&1)) } else { Bad 'node 不可用（注入插件需要 Node.js）' }

# 3) 配置
Write-Output '--- C) 配置'
if (-not (Test-Path $ConfigPath)) {
    Bad ('配置不存在: ' + $ConfigPath + '（从 examples\config.example.json 复制并修改）')
    Write-Output ''
    Write-Output ('RESULT: FAIL  pass=' + $pass + ' fail=' + $fail + ' skip=' + $skip)
    exit 3
}
$cfg = (Get-Content $ConfigPath -Raw | ConvertFrom-Json)
Ok ('配置存在: ' + $ConfigPath)
if ($cfg.server) { Ok ('server = ' + $cfg.server) } else { Bad '配置缺 server' }
if ($cfg.database) { Ok ('database = ' + $cfg.database) } else { Bad '配置缺 database' }

# 4) 数据库连接 + 关键表
Write-Output '--- D) 数据库'
try {
    $cs = 'Server=' + $cfg.server + ';Database=' + $cfg.database + ';TrustServerCertificate=True;Connect Timeout=10'
    if ($cfg.user -and $cfg.password) { $cs += ';User Id=' + $cfg.user + ';Password=' + $cfg.password } else { $cs += ';Integrated Security=True' }
    $cn = New-Object System.Data.SqlClient.SqlConnection $cs
    $cn.Open()
    Ok '数据库可连接'
    $tables = @('memories', 'messages', 'sessions', 'artifacts')
    foreach ($t in $tables) {
        $q = $cn.CreateCommand()
        $q.CommandText = "SELECT CASE WHEN OBJECT_ID('dbo." + $t + "','U') IS NULL THEN 0 ELSE 1 END"
        $has = [int]$q.ExecuteScalar()
        if ($has -eq 1) { Ok ('表存在: dbo.' + $t) } else { Bad ('表缺失: dbo.' + $t + '（把 sql\sqlserver\*.sql 都跑一遍）') }
    }
    $q2 = $cn.CreateCommand(); $q2.CommandText = 'SELECT COUNT(*) FROM dbo.memories'
    Ok ('memories 行数 = ' + $q2.ExecuteScalar())
    $q3 = $cn.CreateCommand(); $q3.CommandText = 'SELECT COUNT(*) FROM dbo.messages'
    Ok ('messages 行数 = ' + $q3.ExecuteScalar())
    $cn.Close()
} catch { Bad ('数据库不可用: ' + $_.Exception.Message.Split("`n")[0]) }

# 5) 引擎读写闭环（用 selftest 作用域，可安全删除）
Write-Output '--- E) 引擎读写'
$engine = Join-Path $RepoRoot 'memory\dsh-mem.ps1'
    $cfgDir = Split-Path $ConfigPath -Parent
if (-not (Test-Path $engine)) { Bad ('找不到引擎: ' + $engine) }
else {
    $token = 'selftest-' + (Get-Date -Format 'HHmmss')
    $saveOut = & cmd.exe /c ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $engine + '" save -Title "' + $token + '" -Body "selftest roundtrip" -Scope machine 2>&1') | Out-String
    $saveLine = ($saveOut -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($saveOut -match 'saved|id=') { Ok ('save 成功: ' + $saveLine.Trim()) }
    else { Bad ('save 失败: ' + $saveLine) }
    Start-Sleep -Seconds 1
    $searchOut = & cmd.exe /c ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $engine + '" search "' + $token + '" 2>&1') | Out-String
    if ($searchOut -match [regex]::Escape($token)) { Ok 'search 能搜到刚写入的那条' } else { Bad 'search 搜不到：注入检索会失效' }
}

# 6) 注入插件
Write-Output '--- F) 注入插件'
$profileDir = Join-Path $env:USERPROFILE '.dsh\profiles\desktop'
$linkPath = Join-Path $profileDir 'node_modules\dsh-memory-bridge'
if (Test-Path $linkPath) {
    Ok ('插件已链接: ' + $linkPath)
    $pkg = Join-Path $profileDir 'package.json'
    if (Test-Path $pkg) {
        $txt = Get-Content $pkg -Raw
        if ($txt -match 'dsh-memory-bridge') { Ok 'package.json 已声明依赖' } else { Bad 'package.json 未声明 dsh-memory-bridge（插件不会加载）' }
    } else { Skp '没找到 profile 的 package.json' }
} else { Bad ('插件未安装: ' + $linkPath + '（见 README 第 3 步）') }

# 7) 副本新鲜度（注入的数据源）
Write-Output '--- G) 离线副本'
$rp = if ($cfg.replicaPath) { $cfg.replicaPath } else { Join-Path (Split-Path $ConfigPath -Parent) 'dsh-mem-replica.json' }
if (-not $cfg.replicaPath) {
    Skp '配置未声明 replicaPath（注入插件可自己指定路径）—— 本项跳过'
}
elseif (Test-Path $rp) {
    $age = ((Get-Date) - (Get-Item $rp).LastWriteTime).TotalMinutes
    if ($age -le 60) { Ok ('副本新鲜（' + [int]$age + ' 分钟前）') } else { Bad ('副本过期 ' + [int]$age + ' 分钟（同步任务没在跑？）') }
}
else { Bad ('副本不存在: ' + $rp + '（引擎的 replica 命令或同步任务没跑过）') }

Write-Output ''
Write-Output ('RESULT: ' + $(if ($fail -eq 0) { 'PASS' } else { 'FAIL' }) + '  pass=' + $pass + ' fail=' + $fail + ' skip=' + $skip)
if ($fail -gt 0) { exit 3 }
