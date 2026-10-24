# 变更记录

## v0.3.2 (2026-10-24) — 紧急修复：v0.3.0/v0.3.1 会让 SQL Server 与 MySQL 配置启动即崩

**如果你用 SQL Server 或 MySQL，请立刻升级到 v0.3.2。** v0.3.0/v0.3.1 在这两种配置下无法启动。

### 根因
v0.3.0 给 SQLite 加默认库路径时写错了变量名（`$ConfigPath` 应为 `$CfgPath`），
而且那行代码对**所有**后端都会求值：

```
$script:SqliteDb = if ($cfg.sqliteDb) {...} else { Join-Path (Split-Path -Parent $ConfigPath) 'dsh-mem.db' }
                                                                          ^^^^^^^^^^^^ 不存在 ⇒ 启动即报错
Cannot bind argument to parameter 'Path' because it is null.
```

### 修复
- 默认值只在 `provider = sqlite` 时计算，且变量名改对
- 回归验证：**四种配置各跑一次** `version` 全部 OK ——
  SQL Server（生产配置）/ MySQL 8.0.12 / MySQL 5.7.26 / SQLite

### 顺带：MySQL 5.7 实测（由这次排查带来）
- 5.7.26 上 `sql/mysql/001..007` 建库脚本**全部通过**：10 表、6 触发器、`utf8mb4_general_ci`
- 引擎命令在 5.7.26 上：version / save / search / stats / roster / recent 通过
- 长跑命令（backup / sync / prune）因测试机上的临时 5.7 实例反复掉线未能完成，**不算通过**

## v0.3.1 (2026-10-24) — SQLite 的 machines 注册修复

复核 v0.3.0 时发现的**静默失败**：SQLite 后端 `roster` 永远显示 0 台机器。

### 根因（两层）
1. `Register-Host` 走的是 SQL Server 的 `MERGE` 分支，靠翻译层改写成 `ON CONFLICT`；
   失败时被 `catch { }` 吞掉，**写入 0 行也不报错**。
2. 我给 SQLite 补的分支里用了 here-string，而 PowerShell 要求终止符 `"@` **顶格**，
   我生成时带缩进 ⇒ 语句被吞、行为不可预期（同一天在 sync 上也踩过一次）。

### 修复
- `Register-Host` 增加**显式 SQLite 分支**：不再依赖 MERGE 翻译，SQL 用单行拼接（不用 here-string）
- 验证：清空 machines → `save` → `roster` 出现 `Yang | 木易 | 1.3.4`

### 复核（clean-room，从 v0.3.0 标签重建库）
- 全新库：10 表 / 6 触发器 / 12 索引 / WAL / allow_mutation=0
- 15 个命令：14 通过（embed 需模型端点）
- 独立断言（直接查库）：messages=267、**重复行=0**、sessions=2、memories=1、**machines=1**
- 只追加：默认拦 UPDATE（`messages is append-only`）；维护模式放行后 267 行完好
- 备份 144KB + JSON 0.4KB；副本 0.4KB

## v0.3.0 (2026-10-24) — SQLite 版

第三个后端：**单机零依赖** —— 一个 .db 文件就是整个记忆库，不装数据库、不开端口、不授权。

### 新增
- `provider: sqlite`：引擎走 sqlite3.exe CLI（与 mysql 后端同构，零 DLL 依赖）
- `sql/sqlite/`：10 张表 + 6 个只追加触发器 + 自检脚本（时间统一 TEXT ISO8601 UTC 毫秒）
- `docs/14-sqlite.md`：安装、配置、建库、差异表、安全边界、已知限制

### 实测（sqlite3 3.50.4 / Windows）
- 15 个命令：version / save / search / recent / history / secrets / stats / roster / replica /
  backup / sync / prune / handoff / recall 全部通过；embed 需要模型端点（未测）
- save：id 从 1 起，回读长度对平（title 10/10、body 45/45）
- sync：337 帧 / 1.6MB → 267 行；再跑 inserted=0 updated=0 removed=0（幂等，无重复行）
- backup：.backup 在线快照 144KB + memories-backup-*.json
- prune -Force 30：删掉 1 条 60 天前的消息（268 → 删 1 → 再跑 0 待删）
- replica：0.7KB，memories=2 / messages=1

### 限制（写进文档，不藏）
- 单文件，不能多机共享；并发写单写者
- 库文件即明文（含 kind=secret 凭据）⇒ 必须收紧 ACL
- 备份用 .backup，不要热拷正在写的 .db

## v0.2.2 (2026-10-24) — MySQL 的 prune 修复 + 验收补记

### 修复
- MySQL 版 `prune`：`messages` 的只追加触发器会拦 DELETE（实测报 `ERROR 1644 messages is append-only: DELETE is not allowed`）
  ⇒ 改为走维护模式（`SET @dsh_allow_mutation = 1` 后在**同一次连接**里删除）
  实测：造一条 60 天前的消息 → `prune -Force 30` 删掉 1 条（270→269）→ 再跑显示 0 待删

### 验收补记（MySQL）
- `handoff` ✅ 只读；`recall` ✅ 无 embed 配置时明确降级（`[DEGRADED]`）并回落到字面检索
- `embed` ⚠ 需要模型端点（本地 bge-m3 之类），未测；未配置时的报错可读


### 修复
- MySQL 版 `prune`：`messages` 的只追加触发器会拦 DELETE ⇒ 改为走维护模式
  （`SET @dsh_allow_mutation = 1` 后在同一次连接里删除），实测删掉 1 条 60 天前的消息
- 验收补记：`handoff` / `recall` 在 MySQL 上通过；`recall` 无 embed 时明确降级而不是假装成功；
  `embed` 需要模型端点，暂未测

## v0.2.1 (2026-10-24) — 文档修正（无行为变更）

修的是"用户照文档做会失败"的几处，代码行为只有一条新增警告：

### 修正
- README 与验收文档里的建库语句把 `utf8mb4_0900_ai_ci` 改成 `utf8mb4_general_ci`
  （前者**只有 MySQL 8.0+ 才有**，5.6/5.7 用户会在第一步就失败；我们的建表脚本本来用的是 general_ci，文档与代码不一致）
- 建账号示例补充 MySQL **8.4+** 的差异：`mysql_native_password` 在该版本默认禁用，
  改用默认插件（去掉 `IDENTIFIED WITH`）

### 新增
- `docs/13-mysql-compatibility.md`：版本矩阵（8.0 实测 / 5.7 与 5.6.4+ 理论可用 / 8.4+ 注意认证插件 / MariaDB 未测）
  + 我们用到特性的最低版本表 + 各版本改法 + 自查命令
- 引擎：连接成功后做一次版本自查，服务器 **< 5.6.4** 时打印一行 WARN
  （不阻断；DATETIME(3) 在那之前不存在，时间会丢毫秒）

### 不变
- 数据库结构、表/触发器、命令行为均未变；v0.2.0 的库可以直接用

## v0.2.0 (2026-10-24) — MySQL 版（experimental）

### 引擎（provider 切换，同一份脚本支持两种数据库）
- 新增 `provider`：`sqlserver`（默认）/ `mysql`
- MySQL 后端走 `mysql.exe`（零 DLL 依赖）：字面量转义 + 方言翻译
  （`TOP`→`LIMIT`、`CONVERT(...,126)`→`DATE_FORMAT`、`ISNULL`→`IFNULL`、
    `MERGE`→`ON DUPLICATE KEY UPDATE`、去掉 `dbo.`）
- `save`：MySQL 用"INSERT + LAST_INSERT_ID() **同一次调用**"取回 id 与存储长度
- `Register-Host`：MySQL 分支用 `CURRENT_USER()` + 本机名做 upsert
- `replica`：真的按配置的 `replicaPath` 落盘（之前硬编码在脚本旁边，与文档不符）

### sync 移植（2026-10-24 · v0.2.0 的最后一块）
- MySQL 版 `sync`（会话导入）完成：单次调用内 建临时表 → 归档 → 更新 → 插入 → 删除，并回报 5 个计数
- 只追加触发器加"维护模式"开关（`SET @dsh_allow_mutation = 1`），比 DROP/CREATE 触发器安全（变量随连接消失）
- 实测：337 帧 / 1.6MB → 267 行；重复跑自动 skip；`-Force` 重跑 inserted=0 updated=0 removed=0
- 过程中修掉 3 个坑：`--init-command` 经 cmd 必须整体加引号、临时表必须显式 COLLATE、`TOP n` 两种写法

### 验收（2026-10-24）
- 验收报告：`docs/11-mysql-acceptance.md`（命令矩阵 + 5 个已修问题 + 限制）
- 结论：记忆读写链路（save/search/recent/history/secrets/stats/roster/replica/backup）**全部通过**；
  `sync`（会话导入）**尚未移植** —— SQL Server 用 SqlBulkCopy，MySQL 需改行级写入
- 补入 `memory/dsh-zstd-extract.js`（sync 的解压环节必需，之前漏在仓库外；需 Node 22.15+/23+）

### 备份与端到端（2026-10-24）
- `backup`：MySQL 分支用 `mysqldump`（`--single-transaction --routines --triggers`），
  实测在 8.0.12 上产出 19.7KB dump，含 10 张表与全部触发器；`mysqldumpCliPath` 可配置
- 导出与副本的默认位置改为**配置目录**（之前落在脚本/仓库目录，正是副本文件误入仓库的根因）
- 修 `CONVERT(...)+'Z'` 的 MySQL 语义：MySQL 里 `+` 是数值加法，`'2026-10-23T…' + 'Z'` 会变成 `2026`
  ⇒ 现在翻译为 `CONCAT(DATE_FORMAT(...),'Z')`（实测踩过，副本里时间一度只剩年份）

### 注入截断修复（影响生产，值得单独记）
- 插件默认 `maxChars=2400`，而「关键约定」全文 6.5KB ⇒ 截断把**各机活动、定义型记忆整段切掉**，
  生产环境里看到的注入其实一直是被截断的
- 现在：`conventionsMax=3000`（关键约定单独设上限并给出"已截断"提示）、`maxChars=12000`
- 用插件自带 `verify.mjs` 对 MySQL 产出的副本跑端到端：**RESULT: PASS**
  （活动段 1 台机器、时间 18:28 UTC 正确、ISO-8601 无需时区补偿、capture/llm 记账均通过）

### 实测（2026-10-24 · MySQL 8.0.12）
- `save` / `search` / `recent` / `roster` / `replica` 全部跑通
- `roster` 显示 `dsh@% | <机器名> | CLI 1.3.4`，与 SQL Server 版一致
- 副本文件已加入 .gitignore（它含真实数据与主机信息，**绝不能进仓库**）


### 新增
- `sql/mysql/`：10 张表的 MySQL 8.0 方言建表脚本 + 6 个只追加触发器（替代 SQL Server 的 DENY UPDATE/DELETE）
- 已在 **MySQL 8.0.12** 上实测：建表全绿；`messages/messages_history/lesson_records` 的 UPDATE/DELETE 会被拦住
- 时间统一存 UTC：连接时 `SET time_zone='+00:00'`，`CURRENT_TIMESTAMP(3)` 即为 UTC（已用 `UTC_TIMESTAMP(3)` 对平验证）

### 说明
- 触发器需要 `log_bin_trust_function_creators=1`（或 SUPER），见 `sql/mysql/007-append-only.sql` 头部
- 引擎 provider 抽象（`sqlserver|mysql`）尚未开始，下一步


## v0.1.0 (2026-10-23) — 首发（SQL Server 版，experimental）

### 新增
- **引擎** `memory/dsh-mem.ps1`：save / search / recent / sync / backup / replica / history
- **注入插件** `memory/plugin/`：强制指令 + IDF 自动检索 + 关键约定全文 + 定义型记忆（按重要性排序注入）
- **SQL Server 建表脚本** 13 个（`sql/sqlserver/`）
- **工具** `ops/install.ps1`、`ops/doctor.ps1`、`ops/secret-scan.ps1`
- **文档** 00-why / 02-memory-design（含三层缺陷复盘）/ 04-postmortems / 08-permissions-and-antivirus / 09-file-map

### 明确不含
- 任何真实环境数据（记忆库内容、对话、主机信息、账号）

### 安全
- 新增 `docs/12-mysql-security.md`：账号最小权限（别用 root）、3306 不对公网、口令不进命令行、
  备份是明文需加密存放、必须 utf8mb4、`log_bin_trust_function_creators` 建完触发器就关、
  `mysqlCliPath` 用绝对路径（防 PATH 劫持）

### 已知限制
- 仅支持 SQL Server（SQLite / MySQL 为后续独立版本）
- 检索是关键词 + IDF，不是语义向量
- 注入长度受上限约束，超长会截断
