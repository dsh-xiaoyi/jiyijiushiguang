# MySQL 版验收报告（2026-10-24）

> 对象：`记忆旧时光 · MySQL 版`（`provider = mysql`，后端走 `mysql.exe`，零 DLL 依赖）
> 测试环境：**MySQL 8.0.12 / Windows 7 SP1 / 库名 dsh_memory**（测试机 · 内网地址不写死）
> 结论：**15 个命令中 11 个通过、4 个未测（handoff / prune / embed / recall），没有阻塞项 —— 可以发正式版 v0.2.0。**

## 一、验收矩阵（15 个命令）

| 命令 | 状态 | 证据（可复核） |
|---|---|---|
| `version` | ✅ | 输出 CLI 1.3.4 与脚本路径/字节数 |
| `save` | ✅ | `saved memory id=5`，readback 长度 12/12 与 18/18 对平 |
| `search` | ✅ | 命中 3 条，正文片段正常 |
| `recent` | ✅ | 列表正常，时间转本地时区正确（说明 UTC 解析对） |
| `history` | ✅ | 空库时输出"(nothing archived yet)"，无报错 |
| `secrets` | ✅ | 无凭据时正常给出提示（SQL Server 专有写法已去除） |
| `stats` | ✅ | sessions=1 / messages=2 / memories=2 / db size=0.4MB |
| `roster` | ✅ | `dsh@% \| <机器名> \| CLI 1.3.4`，与 SQL Server 版一致 |
| `replica` | ✅ | 生成副本 JSON；插件 `verify.mjs` 端到端 **PASS**（活动段 4 台机器、UTC 时间正确） |
| `backup` | ✅ | `mysqldump` 产出 19.7KB dump，含 10 张表 + 6 个触发器 |
| `handoff` | ✅ | 只读；测试库无跨机会话时输出 `no session from another machine found`，无报错 |
| `prune` | ✅ | 干跑正常；`-Force 30` 实测删掉 1 条 60 天前的消息（269→删 1→269），再跑显示 0 待删。<br>**需要维护模式**：messages 有只追加触发器，引擎已改为 `SET @dsh_allow_mutation = 1` 放行 |
| `recall` | ✅ | 无 embed 块时**明确降级**：`semantic: UNAVAILABLE` + `[DEGRADED]` 提示，回落到字面检索（实测命中 messages 20 条），不假装成功 |
| `embed` | ⚠ 待端点 | 未配置时报错清晰（提示加 `embed` 块或 `-BaseURL/-Model`）；真实嵌入需要本地模型端点，本次未测 |
| `sync` | ✅ | 真实会话导入：337 帧 / 1.6MB 文本 → imported user=14 assistant=69 tool=184 total=267；库内 messages=269；再跑 skip unchanged；`-Force` 重跑 **inserted=0 updated=0 removed=0**（幂等）|

## 二、建表脚本验收（`sql/mysql/`）

```
10 张表 + 6 个只追加触发器，8 个脚本依次执行 exit=0
只追加保护实测：UPDATE memories 放行 ✓；UPDATE/DELETE messages 被拦（SQLSTATE 45000）✓；
               UPDATE lesson_records 被拦 ✓
时区：created_at 与 UTC_TIMESTAMP(3) 对平（会话时区 SET time_zone='+00:00' 生效）
```

## 三、移植过程中修掉的问题（都记了根因，避免复现）

| # | 问题 | 根因 | 修法 |
|---|---|---|---|
| 1 | `save` 返回 id=0、长度 0/0 | `LAST_INSERT_ID()` 跨连接为 0（mysql.exe 每次调用=新连接） | INSERT 与取回放进同一次调用 |
| 2 | 行对象全空 | `PSObject` 上的 `get_FieldCount()` 不会被当属性读 | 改成 `NoteProperty FieldCount` |
| 3 | 副本里 `created_at` 只剩 `2026` | MySQL 的 `+` 是数值加法，`'2026-10-23T…' + 'Z'` = 2026 | 翻译成 `CONCAT(DATE_FORMAT(...),'Z')` |
| 4 | `stats`/`secrets` 报 ERROR 1064 | 引擎里 `TOP n`（无括号）没被翻译；还有 `'%'+@p+'%'` 拼接 | 翻译器支持两种 TOP；LIKE 用单参数 |
| 5 | `sync` 找不到解压器 | `dsh-zstd-extract.js` 没进仓库 | 已纳入 `memory/dsh-zstd-extract.js`（需 Node 22.15+/23+） |

## 三之二、安全（单独一页）

部署前务必看 [docs/12-mysql-security](12-mysql-security.md)：账号最小权限、3306 不对公网、口令不进命令行、
备份是明文需加密、utf8mb4、`log_bin_trust_function_creators` 用完要关、`mysqlCliPath` 用绝对路径。

## 四、已知限制（照实写）

```
· `handoff` / `prune` / `embed` / `recall` 未在 MySQL 上验证（前两个是读/删历史，后两个要 embed 配置）
· 触发器需要 log_bin_trust_function_creators=1（或 SUPER），见 sql/mysql/007 头部
· 每次查询起一个 mysql.exe 进程（~50-100ms）；对"每轮几次查询"够用，但不适合高频批量
· embed/recall（语义检索）未验证；向量表结构已建
· 只测了 MySQL 8.0.12 + Windows；5.7 / Linux 未测
```

## 五、发布建议

| 方案 | 内容 | 我的建议 |
|---|---|---|
| A | 现在就发 **v0.2.0-beta**，明确写"sync 未移植" | 可接受，但用户会问"为什么我的对话没进库" |
| B | **先补齐 sync（行级写入 + ON DUPLICATE KEY UPDATE），再发 v0.2.0** | ★ 推荐；估计半天 |
| C | 暂不发，等 SQLite 版一起 | 太保守 |

## 六、复现步骤（任何人可重跑）

```bash
mysql -uroot -p -e "CREATE DATABASE dsh_memory CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
for f in sql/mysql/0*.sql; do mysql --defaults-extra-file=my.cnf --init-command="SET time_zone='+00:00'" dsh_memory < "$f"; done

# 配置里 provider=mysql + mysqlCliPath 指向 mysql.exe
powershell -File memory\dsh-mem.ps1 save -Title 测试 -Body 你好 -Scope global
powershell -File memory\dsh-mem.ps1 search 测试
powershell -File memory\dsh-mem.ps1 stats
powershell -File memory\dsh-mem.ps1 backup
node memory\plugin\verify.mjs        # 端到端注入自检，应 RESULT: PASS
```

## 七、sync（会话导入）在 MySQL 上的实现（2026-10-24 补齐）

```
SQL Server 用 #临时表 + SqlBulkCopy；MySQL 没有等价物，而且 mysql.exe **每次调用都是新连接**，
所以整个写作阶段放进**一次**调用：
  建临时表（显式 COLLATE=utf8mb4_general_ci，否则字符串比较报 1267）
  → 分批 INSERT 灌数据（每 100 行一条 INSERT）
  → 归档 dropped/changed 到 messages_history
  → UPDATE 变更行 → INSERT 新行 → DELETE 已消失的 seq
  → SELECT 五个计数（dropped/changed/inserted/updated/removed）

只追加触发器怎么兼容？
  触发器里加了维护开关：默认 `@dsh_allow_mutation IS NULL` ⇒ 拦；
  sync 的脚本开头 `SET @dsh_allow_mutation = 1;` ⇒ 放行。
  变量随连接消失，所以不存在"忘了恢复"的风险（比 DROP TRIGGER 更安全）。

实测（2026-10-24）：
  337 帧 / 1.6MB 文本 → 267 行；重复跑 skip；-Force 重跑 inserted=0 updated=0 removed=0
```

## 八、第二轮验收补充（handoff / prune / recall）

```
handoff  ✅ 只读，无跨机会话时输出 "no session from another machine found"
prune    ✅ 干跑 + -Force 都通过；但 messages 的只追加触发器会拦 DELETE
            ⇒ 引擎已改为在 MySQL 上走维护模式（SET @dsh_allow_mutation = 1），
              实测：造一条 60 天前的消息 → prune -Force 30 删掉 → 再跑显示 0 待删
recall   ✅ 没有 embed 配置时**明确降级**（semantic: UNAVAILABLE + [DEGRADED]），
            回落到字面检索并给出命中数 —— 这是正确行为：宁可说"降级"，不假装"语义检索成功"
embed    ⚠ 需要模型端点（bge-m3 之类），本次未测；未配置时的报错信息是可读的
```
