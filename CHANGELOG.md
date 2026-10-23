# 变更记录

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
