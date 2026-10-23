# Roadmap

> 顺序按"对用户门槛的降低程度"排，不按技术兴趣排。

## v0.1.0（当前，已完成）— SQL Server 版

- [x] 引擎 CLI：`save` / `search` / `recent` / `sync` / `backup` / `replica` / `history`
- [x] 注入插件：强制指令 + IDF 自动检索 + 关键约定全文 + 定义型记忆
- [x] SQL Server 建表脚本（13 个）
- [x] 体检脚本 `ops\doctor.ps1`、安装脚本 `ops\install.ps1`
- [x] 文档：为什么做 / 设计 / 复盘 / 权限与安全软件 / 文件地图

## v0.3.0 — SQLite 版（单独版本）

- [ ] 驱动：改用无需安装的服务端数据库（单文件）
- [ ] SQL 方言移植：`sql/sqlite/*.sql`
- [ ] 引擎：抽象"连接 / 执行 / 参数 / 取单值"四层，按 `-Provider sqlite` 切换
- [ ] 备份：`.db` 文件级快照（VACUUM INTO 或文件复制 + 校验）
- [ ] 测试：全新 Windows 上"零安装"跑通完整闭环
- [ ] 文档：SQLite 版 README（默认路径、单机最佳实践）

## v0.2.0 — MySQL 版（进行中 · DDL 已在 MySQL 8.0.12 验证通过）

- [x] 后端选型：**mysql.exe 命令行走**（零额外依赖；MySqlConnector 在 PS 5.1 要 7 个 DLL，放弃）
- [x] SQL 方言移植：`sql/mysql/*.sql`（10 表 + 6 触发器，实测建表通过）
- [x] 只追加保护：BEFORE UPDATE/DELETE 触发器 + SIGNAL（等价 SQL Server 的 DENY）
- [ ] 引擎 provider 抽象（`provider: sqlserver|mysql`）与参数转义
- [ ] 备份：mysqldump / mysql < file
- [ ] 备份：`mysqldump` / `mysql < file`
- [x] 建表验证：MySQL 8.0.12（Win7 测试机）10 表 + 6 触发器全部建成
- [ ] 端到端：save/search/replica 走 mysql 后端
- [ ] 文档：MySQL 版 README（建库授权、字符集 utf8mb4、时区）

## v0.4.0 — 检索升级（可选）

- [ ] 向量检索接入（embeddings 表已就位，缺 embedding 生成与召回）
- [ ] 混合排序：关键词 IDF + 向量相似度

## 原则

- 每个数据库版本**独立目录、独立发布**，不做"同一份代码到处 if"
- 每个版本发布前必须：语法检查 + secret-scan + 全新机器安装演练
- 不改用户机器上的安全设置；杀软拦截一律走"加白名单"
