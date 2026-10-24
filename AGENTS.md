# AGENTS.md —— 给"智能体"看的安装与验收说明

> 你是另一个 DSH（或别的编码智能体)，想把这个项目装到自己的机器上。
> 这一页只写**可执行步骤 + 判定标准**，不解释设计理念（那看 README / docs）。

## 0. 先判断"你能不能用"

```
必须：Windows + PowerShell 5.1+（Linux/macOS 不行，引擎是 PowerShell）
必须：Node.js（记忆注入插件需要）；只有 CLI 用法可以不要
必须：一个数据库（三选一，见下表）
必须：DSH 本体（本项目是"DSH 的记忆层 + 插件"，不能单独跑成智能体）
```

| 后端 | 额外依赖 | 难度 | 适合 |
|---|---|---|---|
| `sqlite` | `sqlite3.exe`（3.33+，单文件） | ★ 最低 | 单机、零安装 |
| `mysql` | `mysql.exe` + 一个 MySQL 5.6.4+ 实例 | ★★ | 多机共享 |
| `sqlserver` | `sqlcmd` + SQL Server 实例 | ★★★ | 已有授权 |

## 1. 非交互安装（一条命令）

```powershell
# 最省事：SQLite（自动建库文件 + 建表 + 体检）
powershell -ExecutionPolicy Bypass -File .\ops\install.ps1 -Provider sqlite `
    -SqliteDb C:\dsh-mem\data\dsh-mem.db

# MySQL（口令放文件里，别上命令行）
powershell -ExecutionPolicy Bypass -File .\ops\install.ps1 -Provider mysql `
    -MySqlServer 127.0.0.1,3306 -MySqlUser dsh -MySqlDatabase dsh_memory `
    -MySqlPasswordFile C:\temp\mysql-pw.txt

# SQL Server
powershell -ExecutionPolicy Bypass -File .\ops\install.ps1 -Provider sqlserver `
    -SqlServer '127.0.0.1,1433' -Database DSHMemory
```

常用开关：`-SkipDdl`（只写配置）/ `-SkipPlugin`（不装注入插件）/ `-RegisterTasks`（注册定时任务）。

## 2. 判定"装好了"（不要只看退出码）

```powershell
$eng = '.\memory\dsh-mem.ps1'
$cfg = 'C:\dsh-mem\dsh-mem.config.json'
$env:DSH_MEM_CONFIG = $cfg

powershell -File $eng version          # 应打印 cli/file/limits/server
powershell -File $eng save -Title '安装自检' -Body 'hello' -Kind fact
powershell -File $eng stats            # 应打印 sessions/messages/memories/size
powershell -File $eng roster           # 本机必须出现（machines ≥ 1）
```

**四条硬判据**（缺一条就不算装好）：

```
① save 的输出里 readback 左右两个数字相等（title n/n、body n/n）
② stats 的 messages 计数 ≥ 1
③ roster 里能看到本机（不是 0 台）
④ 直接查库：COUNT(*) 与 COUNT(DISTINCT session_id,seq) 相等（SQLite: session_id||'/'||seq）
```

第 ④ 条别省 —— "写 0 行也算成功"是本项目历史上真实踩过的坑（v0.3.1 的 SQLite 就栽在这）。

## 3. 常见失败与定位

| 现象 | 原因 | 处理 |
|---|---|---|
| `config not found` | 没设 `DSH_MEM_CONFIG`，也不在默认路径 | 设环境变量或把配置放到 `C:\dsh-mem\dsh-mem.config.json` |
| `Cannot bind argument to parameter 'Path'` | 用了 v0.3.0/0.3.1（已知缺陷） | 升级到 v0.3.3+ |
| `ERROR 2003` / `Can't connect` | MySQL 没起 / 端口 / 防火墙 | 先 `mysql -h ... -e "SELECT 1"` 验证 |
| `mysqldump: Got error: 2003` | 备份时连不上 | 同上；备份需要客户端能连库 |
| `unknown function: LEFT`（sqlite） | 引擎版本过旧 | 升级到 v0.3.3+ |
| `no such table: _guard_state` | 没跑 `sql/sqlite/001` | 按顺序执行 DDL |
| `extractor not found` | 引擎旁边缺 `dsh-zstd-extract.js` | 从 `memory/` 一起拷过去 |
| `ERROR 1419`（建触发器时） | MySQL 开了 binlog 但账号没 SUPER | 用 root 执行一次 `SET GLOBAL log_bin_trust_function_creators = 1;`（想持久化写进 my.ini） |

## 4. 只追加保护（装完必须验证一次）

```powershell
# 插一行再改它，必须被拒
sqlite3 <db> "INSERT INTO messages (session_id,seq,role,text) VALUES ('t',1,'user','x')"
sqlite3 <db> "UPDATE messages SET role='y' WHERE session_id='t'"
# 期望：messages is append-only: UPDATE is not allowed
```

## 5. 插件装好后要重启 DSH

```
· 插件目录 link 到 <profile>\node_modules\dsh-memory-bridge
· 还要在 DSH 的 package.json 里声明该依赖
· 然后**重启 DSH**（不重启不会加载）
· 验证：会话里应出现「强制指令 / 相关记忆」段落（docs/15 有自查方法）
```

## 6. 不要做的事

```
· 不要把真实口令写进聊天/日志/仓库（用 -SecretFile / 环境变量 / 密码库）
· 不要把 *.json 副本、备份、.db 提交进 git
· 不要用 v0.3.0 / v0.3.1（SQL Server 与 MySQL 配置启动即崩）
· 不要在多台机器共享同一个 SQLite 文件（单文件、单写者）
```
