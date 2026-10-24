# 第一次用？先看 README 的「5 分钟跑起来」，再回来读这个脚本。
# install.ps1 - 一键安装（单机最小闭环）· 支持 sqlserver / mysql / sqlite
#
# 只做"能把记忆跑起来"的最小动作，不修改系统安全设置、不安装第三方杀软、不联网下载。
# 前置：Windows + PowerShell 5.1+、Node.js（注入插件需要）、以及所选后端的客户端：
#   sqlserver : sqlcmd（SQL Server 或 ODBC Driver 自带）
#   mysql     : mysql.exe（mysqlCliPath 或 PATH）、一个可连的 MySQL 5.6.4+
#   sqlite    : sqlite3.exe（sqliteCliPath 或 PATH）——最省事，零安装
param(
    [ValidateSet('sqlserver', 'mysql', 'sqlite')]
    [string]$Provider = 'sqlserver',

    [string]$ConfigPath = 'C:\dsh-mem\dsh-mem.config.json',

    # --- SQL Server ---
    [string]$SqlServer  = '127.0.0.1,1433',
    [string]$Database   = 'DSHMemory',

    # --- MySQL ---
    [string]$MySqlServer = '127.0.0.1,3306',
    [string]$MySqlUser   = 'dsh',
    [string]$MySqlDatabase = 'dsh_memory',
    [string]$MySqlPasswordFile = '',   # 口令从文件读（避免进命令行/历史）
    [string]$MySqlCli = '',           # mysql.exe 路径；留空则用 DSH_MYSQL_CLI 环境变量或 PATH
    [string]$MySqlDumpCli = '',       # mysqldump.exe 路径；留空则用同一目录下的

    # --- SQLite ---
    [string]$SqliteCli = '',
    [string]$SqliteDb  = 'C:\dsh-mem\data\dsh-mem.db',

    [switch]$SkipDdl,
    [switch]$SkipPlugin,
    [switch]$SkipReplica,
    [switch]$RegisterTasks,
    [string]$SessionsRoot = ''
)
$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host ('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $m) }

if (-not $SessionsRoot) { $SessionsRoot = Join-Path $env:USERPROFILE '.dsh\sessions' }
$repoRoot = Split-Path $PSScriptRoot -Parent

function Test-Prerequisites {
    $missing = @()
    if (-not $SkipPlugin -and -not (Get-Command node -ErrorAction SilentlyContinue)) {
        $missing += 'node（Node.js，记忆注入插件需要；不想装插件就加 -SkipPlugin）'
    }
    switch ($Provider) {
        'sqlserver' {
            if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
                $missing += 'sqlcmd（SQL Server 命令行工具，装 SQL Server 或 ODBC Driver 时自带）'
            }
        }
        'mysql' {
            $cli = if ($MySqlCli) { $MySqlCli } elseif ($env:DSH_MYSQL_CLI) { $env:DSH_MYSQL_CLI } else { 'mysql' }
            if (-not (Get-Command $cli -ErrorAction SilentlyContinue) -and -not (Test-Path $cli)) {
                $missing += 'mysql.exe（用 -MySqlCli 指定绝对路径，或装到 PATH / 设 DSH_MYSQL_CLI）'
            }
        }
        'sqlite' {
            $cli = if ($SqliteCli) { $SqliteCli } else { 'sqlite3' }
            if (-not (Get-Command $cli -ErrorAction SilentlyContinue) -and -not (Test-Path $cli)) {
                $missing += 'sqlite3.exe（SQLite 命令行工具，3.33+；放到 PATH 或用 -SqliteCli 指定绝对路径）'
            }
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host ''
        Write-Host '还差这些前置条件（装好后再跑一次）：' -ForegroundColor Yellow
        foreach ($m in $missing) { Write-Host ('  · ' + $m) -ForegroundColor Yellow }
        Write-Host '  说明：本脚本不改系统安全设置、不联网下载任何东西。' -ForegroundColor DarkGray
        throw '前置条件不足'
    }
}

function New-Config {
    $existing = $null
    if (Test-Path $ConfigPath) { $existing = Get-Content $ConfigPath -Raw | ConvertFrom-Json }
    $cfg = [ordered]@{}
    $cfg.provider    = $Provider
    $cfg.replicaPath = ($existing.replicaPath)
    if (-not $cfg.replicaPath) { $cfg.replicaPath = (Join-Path (Split-Path $ConfigPath -Parent) 'dsh-mem-replica.json') }
    $cfg.sessionsRoot = $SessionsRoot
    switch ($Provider) {
        'sqlserver' {
            $cfg.server   = $SqlServer
            $cfg.database = $Database
            $cfg.user     = if ($existing.user) { $existing.user } else { 'dsh_app' }
            $cfg.password = if ($existing.password) { $existing.password } else { 'CHANGE_ME' }
        }
        'mysql' {
            $cfg.server   = $MySqlServer
            $cfg.database = $MySqlDatabase
            $cfg.user     = if ($existing.user) { $existing.user } else { $MySqlUser }
            $cfg.password = if ($existing.password -and $existing.password -ne 'CHANGE_ME') { $existing.password }
                            elseif ($MySqlPasswordFile -and (Test-Path $MySqlPasswordFile)) { (Get-Content $MySqlPasswordFile -Raw).Trim() }
                            else { 'CHANGE_ME' }
            $cliResolved = if ($MySqlCli) { $MySqlCli } elseif ($env:DSH_MYSQL_CLI) { $env:DSH_MYSQL_CLI } elseif ($existing.mysqlCliPath) { $existing.mysqlCliPath } else { '' }
            $cfg.mysqlCliPath = $cliResolved
            $dumpResolved = if ($MySqlDumpCli) { $MySqlDumpCli } elseif ($existing.mysqldumpCliPath) { $existing.mysqldumpCliPath } elseif ($cliResolved) {
                $d = Join-Path (Split-Path $cliResolved -Parent) 'mysqldump.exe'
                if (Test-Path $d) { $d } else { '' }
            } else { '' }
            $cfg.mysqldumpCliPath = $dumpResolved
        }
        'sqlite' {
            $cfg.sqliteDb      = $SqliteDb
            $cfg.sqliteCliPath = if ($SqliteCli) { $SqliteCli } else { if ($existing.sqliteCliPath) { $existing.sqliteCliPath } else { '' } }
        }
    }
    $json = [pscustomobject]$cfg | ConvertTo-Json
    [System.IO.File]::WriteAllText($ConfigPath, $json, (New-Object System.Text.UTF8Encoding $false))
    Say ('   已写 ' + $ConfigPath + '（provider=' + $Provider + '）')
}

function Invoke-SqlServerDdl {
    Say ('2.5/5 确保数据库存在: ' + $Database)
    $chkSql = "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'" + $Database + "') IS NULL THEN 0 ELSE 1 END"
    $chk = & cmd.exe /c ('sqlcmd -E -S ' + $SqlServer + ' -h -1 -W -Q "' + $chkSql + '" 2>&1') | Out-String
    if ($chk -match '^\s*0\s*$') {
        Say '   数据库不存在，创建中...'
        & cmd.exe /c ('sqlcmd -E -S ' + $SqlServer + ' -b -Q "CREATE DATABASE [' + $Database + ']"') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '建库失败（确认实例名正确、且你有 sysadmin/建库权限）' }
    }
    $sqlDir = Join-Path $repoRoot 'sql\sqlserver'
    $files = @(Get-ChildItem $sqlDir -Filter '*.sql' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($files.Count -eq 0) { throw ('没有找到 SQL 脚本: ' + $sqlDir) }
    foreach ($f in $files) {
        Say ('   - ' + $f.Name)
        & cmd.exe /c ('sqlcmd -E -S ' + $SqlServer + ' -d ' + $Database + ' -b -i "' + $f.FullName + '"')
        if ($LASTEXITCODE -ne 0) { throw ('SQL 执行失败: ' + $f.Name + '（exit=' + $LASTEXITCODE + '）') }
    }
}

function Invoke-MySqlDdl {
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $cli = if ($cfg.mysqlCliPath) { $cfg.mysqlCliPath } else { 'mysql' }
    # 只有"路径"才需要引号；裸命令名（PATH 里的 mysql）加引号会让 cmd 找不到
    $cliArg = if ($cli -match '[\\/]') { '"' + $cli + '"' } else { $cli }
    $pw = [string]$cfg.password
    if (-not $pw -or $pw -eq 'CHANGE_ME') {
        if ($MySqlPasswordFile -and (Test-Path $MySqlPasswordFile)) {
            $pw = (Get-Content $MySqlPasswordFile -Raw).Trim()
        } else {
            throw ('需要 MySQL 口令：先把 config 里的 password 改成真实口令，或用 -MySqlPasswordFile 指向一个只含口令的文件')
        }
    }
    $cnf = [System.IO.Path]::GetTempFileName()
    try {
        $hostPart = ([string]$cfg.server).Split(',')[0]
        $portPart = '3306'
        if (([string]$cfg.server) -match ',\s*(\d+)\s*$') { $portPart = $matches[1] }
        $lines = @('[client]',
                   ('user=' + [string]$cfg.user),
                   ('password=' + $pw),
                   ('host=' + $hostPart),
                   ('port=' + $portPart),
                   'default-character-set=utf8mb4')
        [System.IO.File]::WriteAllText($cnf, ($lines -join "`r`n"), (New-Object System.Text.ASCIIEncoding))
        Say ('2.5/5 确保数据库存在: ' + $cfg.database)
        & cmd.exe /c ($cliArg + ' --defaults-extra-file="' + $cnf + '" -e "CREATE DATABASE IF NOT EXISTS `' + $cfg.database + '` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" 2>&1')
        if ($LASTEXITCODE -ne 0) { throw 'MySQL 连接或建库失败（检查 server/user/password 与授权）' }
        $sqlDir = Join-Path $repoRoot 'sql\mysql'
        $files = @(Get-ChildItem $sqlDir -Filter '*.sql' | Sort-Object Name)
        if ($files.Count -eq 0) { throw ('没有找到 SQL 脚本: ' + $sqlDir) }
        foreach ($f in $files) {
            Say ('   - ' + $f.Name)
            $out = & cmd.exe /c ($cliArg + ' --defaults-extra-file="' + $cnf + '" ' + $cfg.database + ' < "' + $f.FullName + '" 2>&1') | Out-String
            if ($LASTEXITCODE -ne 0) {
                if ($out -match '1419|log_bin_trust_function_creators') {
                    Write-Host ''
                    Write-Host '建触发器被 MySQL 拒绝（ERROR 1419）：开了 binlog 又没 SUPER 权限。' -ForegroundColor Yellow
                    Write-Host '两种解法（任选一种，只需要一次）：' -ForegroundColor Yellow
                    Write-Host '  A. 用 root 执行一次：SET GLOBAL log_bin_trust_function_creators = 1;' -ForegroundColor Yellow
                    Write-Host '     （想重启后仍生效：写进 my.ini 的 [mysqld] 段：log_bin_trust_function_creators=1）' -ForegroundColor Yellow
                    Write-Host '  B. 给应用账号 SUPER 权限（不推荐），或用没开 binlog 的实例。' -ForegroundColor Yellow
                    Write-Host '详见 docs/12-mysql-security.md 第三节。' -ForegroundColor DarkGray
                }
                throw ('SQL 执行失败: ' + $f.Name + '（exit=' + $LASTEXITCODE + '）')
            }
        }
    } finally { Remove-Item -LiteralPath $cnf -Force -ErrorAction SilentlyContinue }
}

function Invoke-SqliteDdl {
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $cli = if ($cfg.sqliteCliPath) { $cfg.sqliteCliPath } else { 'sqlite3' }
    $cliArg = if ($cli -match '[\\/]') { '"' + $cli + '"' } else { $cli }
    $db = [string]$cfg.sqliteDb
    $dir = Split-Path $db -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Say ('2.5/5 建库文件: ' + $db)
    $sqlDir = Join-Path $repoRoot 'sql\sqlite'
    $files = @(Get-ChildItem $sqlDir -Filter '*.sql' | Sort-Object Name)
    if ($files.Count -eq 0) { throw ('没有找到 SQL 脚本: ' + $sqlDir) }
    foreach ($f in $files) {
        Say ('   - ' + $f.Name)
        & cmd.exe /c ($cliArg + ' "' + $db + '" ".read ' + $f.FullName + '"')
        if ($LASTEXITCODE -ne 0) { throw ('SQL 执行失败: ' + $f.Name + '（exit=' + $LASTEXITCODE + '）') }
    }
}

Test-Prerequisites

Say ('1/5 准备目录 ' + (Split-Path $ConfigPath -Parent))
New-Item -ItemType Directory -Path (Split-Path $ConfigPath -Parent) -Force | Out-Null

Say '2/5 生成配置（provider=' + $Provider + '）'
New-Config

if (-not $SkipDdl) {
    Say '3/5 建库建表（后端 = ' + $Provider + '）'
    switch ($Provider) {
        'sqlserver' { Invoke-SqlServerDdl }
        'mysql'     { Invoke-MySqlDdl }
        'sqlite'    { Invoke-SqliteDdl }
    }
} else { Say '3/5 跳过 DDL' }

if (-not $SkipReplica) {
    Say '3.5/5 生成第一份离线副本（注入插件读它）'
    try {
        $env:DSH_MEM_CONFIG = (Resolve-Path $ConfigPath).Path
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'memory\dsh-mem.ps1') replica | Out-Null
        Say '   已生成'
    } catch { Say ('   WARN 生成副本失败（不影响安装，稍后可手动跑 replica）: ' + $_.Exception.Message.Split("`n")[0]) }
}

Say '4/5 安装记忆注入插件'
if ($SkipPlugin) { Say '   已跳过（-SkipPlugin）' }
else {
    $pluginSrc = (Resolve-Path (Join-Path $repoRoot 'memory\plugin')).Path
    $profileDir = Join-Path $env:USERPROFILE '.dsh\profiles\desktop'
    $nm = Join-Path $profileDir 'node_modules'
    New-Item -ItemType Directory -Path $nm -Force | Out-Null
    $target = Join-Path $nm 'dsh-memory-bridge'
    if (Test-Path $target) { Say '   已存在，跳过（要更新请手动替换）' }
    else {
        cmd /c mklink /D "$target" "$pluginSrc" | Out-Null
        Say ('   已链接: ' + $target + ' → ' + $pluginSrc)
        Say '   ★ 还需在 DSH 的 package.json 里声明依赖，然后**重启 DSH**，否则插件不会加载'
    }
}

if ($RegisterTasks) {
    Say '4.5/5 注册计划任务（会话导入 + 副本刷新）'
    $eng = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'memory\dsh-mem.ps1'))
    $common = ' -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoLogo -File "' + $eng + '"'
    & cmd.exe /c ('schtasks /create /tn "DSH_MemReplica" /tr "powershell.exe' + $common + ' replica" /sc minute /mo 1 /ru SYSTEM /rl HIGHEST /f') | Out-Null
    Say '   DSH_MemReplica 每 1 分钟（把数据库导出成插件读的副本）'
    & cmd.exe /c ('schtasks /create /tn "DSH_MemSync" /tr "powershell.exe' + $common + ' sync -All -IncludeTools" /sc minute /mo 3 /ru SYSTEM /rl HIGHEST /f') | Out-Null
    Say '   DSH_MemSync 每 3 分钟（把新会话导入数据库）'
    Say '   ★ 若数据库用 SQL 登录，SYSTEM 账户连不上：把 /ru SYSTEM 换成你的账号'
} else { Say '4.5/5 跳过计划任务（-RegisterTasks 可自动注册；不注册时插件会在副本过期时自动刷新）' }

Say '5/5 体检'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'doctor.ps1') -ConfigPath $ConfigPath
