# 第一次用？先看 README 的「5 分钟跑起来」，再回来读这个脚本。
# install.ps1 - 多智能体集群 · 一键安装（单机最小闭环）
#
# 只做"能把记忆跑起来"的最小动作，不修改系统安全设置、不安装第三方杀软、不联网下载。
# 需要：Windows + PowerShell 5.1+、SQL Server（Express 可用）、Node.js（青鸟插件需要）
param(
    [string]$ConfigPath = 'C:\dsh-mem\dsh-mem.config.json',
    [string]$SqlServer  = '127.0.0.1,1433',
    [string]$Database   = 'DSHMemory',
    [switch]$SkipDdl,
    [switch]$RegisterTasks,
    [string]$SessionsRoot = ''
)
$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host ('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $m) }

function Test-Prerequisites {
    # 缺依赖要"吵"，不要默默跑一半
    $missing = @()
    if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) { $missing += 'sqlcmd（SQL Server 命令行工具，装 SQL Server 或 ODBC Driver 时自带）' }
    if (-not (Get-Command node   -ErrorAction SilentlyContinue)) { $missing += 'node（Node.js，青鸟/记忆注入插件需要）' }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($missing.Count -gt 0) {
        Write-Host ''
        Write-Host '还差这些前置条件（装好后再跑一次）：' -ForegroundColor Yellow
        foreach ($m in $missing) { Write-Host ('  · ' + $m) -ForegroundColor Yellow }
        Write-Host '  说明：本脚本不改系统安全设置、不联网下载任何东西。' -ForegroundColor DarkGray
        throw '前置条件不足'
    }
    if (-not $isAdmin) {
        Write-Host '提示：当前不是管理员。建表/建库那一步需要 sysadmin 连接；如果只是验证流程可以先跳过 DDL。' -ForegroundColor Yellow
    }
}


Test-Prerequisites

Say '1/5 准备目录 C:\dsh-mem'
New-Item -ItemType Directory -Path 'C:\dsh-mem' -Force | Out-Null

Say '2/5 生成配置（若已存在则跳过）'
if (-not (Test-Path $ConfigPath)) {
    $example = Join-Path $PSScriptRoot '..\examples\config.example.json'
    if (Test-Path $example) {
        $t = Get-Content $example -Raw
        $t = $t -replace '192\.0\.2\.11,1433', $SqlServer -replace 'DSHMemory', $Database
        [System.IO.File]::WriteAllText($ConfigPath, $t, (New-Object System.Text.UTF8Encoding $false))
        Say ('   已生成 ' + $ConfigPath + '（请按需修改 user/password）')
    } else { throw '找不到 examples\config.example.json' }
} else { Say '   已存在，跳过' }

# 建库（若不存在）+ 补 sessionsRoot
if (-not $SkipDdl) {
    Say ('2.5/5 确保数据库存在: ' + $Database)
    $chkSql = "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'" + $Database + "') IS NULL THEN 0 ELSE 1 END"
    $chk = & cmd.exe /c ('sqlcmd -E -S ' + $SqlServer + ' -h -1 -W -Q "' + $chkSql + '" 2>&1') | Out-String
    if ($chk -match '^\s*0\s*$') {
        Say '   数据库不存在，创建中...'
        & cmd.exe /c ('sqlcmd -E -S ' + $SqlServer + ' -b -Q "CREATE DATABASE [' + $Database + ']"') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '建库失败（确认实例名正确、且你有 sysadmin/建库权限）' }
        Say '   已创建'
    } else { Say '   已存在' }
}

if (-not $SessionsRoot) { $SessionsRoot = Join-Path $env:USERPROFILE '.dsh\sessions' }
if (Test-Path $ConfigPath) {
    try {
        $cj = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        if (-not $cj.sessionsRoot) {
            $cj | Add-Member -NotePropertyName sessionsRoot -NotePropertyValue $SessionsRoot -Force
            $cj | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
            Say ('   已写入 sessionsRoot = ' + $SessionsRoot)
        } else { Say ('   sessionsRoot 已存在: ' + $cj.sessionsRoot) }
    } catch { Say ('   WARN 写 sessionsRoot 失败: ' + $_.Exception.Message.Split("`n")[0]) }
}

if (-not $SkipDdl) {
    Say '3/5 建库建表（需要 sysadmin；失败会停下并提示）'
    $sqlDir = Join-Path $PSScriptRoot '..\sql\sqlserver'
    $files = @(Get-ChildItem $sqlDir -Filter '*.sql' | Sort-Object Name)
    if ($files.Count -eq 0) { throw ('没有找到 SQL 脚本: ' + $sqlDir) }
    foreach ($f in $files) {
        Say ('   - ' + $f.Name)
        & cmd.exe /c ('sqlcmd -E -S ' + $SqlServer + ' -d ' + $Database + ' -b -i "' + $f.FullName + '"')
        if ($LASTEXITCODE -ne 0) { throw ('SQL 执行失败: ' + $f.Name + '（exit=' + $LASTEXITCODE + '）') }
    }
} else { Say '3/5 跳过 DDL' }

Say '4/5 安装记忆注入插件（link 到本仓库）'
$pluginSrc = Resolve-Path (Join-Path $PSScriptRoot '..\memory\plugin')
$profileDir = Join-Path $env:USERPROFILE '.dsh\profiles\desktop'
$nm = Join-Path $profileDir 'node_modules'
New-Item -ItemType Directory -Path $nm -Force | Out-Null
$target = Join-Path $nm 'dsh-memory-bridge'
if (Test-Path $target) { Say '   已存在，跳过（要更新请手动替换）' }
else {
    cmd /c mklink /D "$target" "$pluginSrc" | Out-Null
    Say ('   已链接: ' + $target + ' → ' + $pluginSrc)
    Say '   ★ 还需要在 package.json 里声明依赖，然后**重启 DSH**，否则插件不会加载'
}

if ($RegisterTasks) {
    Say '4.5/5 注册计划任务（会话导入 + 副本刷新）'
    $eng = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\memory\dsh-mem.ps1'))
    $common = ' -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoLogo -File "' + $eng + '"'
    & cmd.exe /c ('schtasks /create /tn "DSH_MemReplica" /tr "powershell.exe' + $common + ' replica" /sc minute /mo 1 /ru SYSTEM /rl HIGHEST /f') | Out-Null
    Say '   DSH_MemReplica 每 1 分钟（把数据库导出成插件读的副本）'
    & cmd.exe /c ('schtasks /create /tn "DSH_MemSync" /tr "powershell.exe' + $common + ' sync -All -IncludeTools" /sc minute /mo 3 /ru SYSTEM /rl HIGHEST /f') | Out-Null
    Say '   DSH_MemSync 每 3 分钟（把新会话导入数据库）'
    Say '   ★ 若数据库用 SQL 登录（非 Windows 认证），SYSTEM 账户连不上：把 /ru SYSTEM 换成你的账号'
}
else { Say '4.5/5 跳过计划任务（-RegisterTasks 可自动注册；不注册时插件会在副本过期时自动刷新）' }

Say '5/5 体检'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'doctor.ps1') -ConfigPath $ConfigPath
