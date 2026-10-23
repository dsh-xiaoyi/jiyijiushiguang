# 变更记录

## 未发布 — MySQL 版（v0.2.0 候选）

### 引擎（provider 切换，同一份脚本支持两种数据库）
- 新增 `provider`：`sqlserver`（默认）/ `mysql`
- MySQL 后端走 `mysql.exe`（零 DLL 依赖）：字面量转义 + 方言翻译
  （`TOP`→`LIMIT`、`CONVERT(...,126)`→`DATE_FORMAT`、`ISNULL`→`IFNULL`、
    `MERGE`→`ON DUPLICATE KEY UPDATE`、去掉 `dbo.`）
- `save`：MySQL 用"INSERT + LAST_INSERT_ID() **同一次调用**"取回 id 与存储长度
- `Register-Host`：MySQL 分支用 `CURRENT_USER()` + 本机名做 upsert
- `replica`：真的按配置的 `replicaPath` 落盘（之前硬编码在脚本旁边，与文档不符）

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

### 已知限制
- 仅支持 SQL Server（SQLite / MySQL 为后续独立版本）
- 检索是关键词 + IDF，不是语义向量
- 注入长度受上限约束，超长会截断
