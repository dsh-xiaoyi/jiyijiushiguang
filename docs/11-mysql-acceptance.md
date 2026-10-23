# MySQL 版验收报告（2026-10-24）

> 对象：`记忆旧时光 · MySQL 版`（`provider = mysql`，后端走 `mysql.exe`，零 DLL 依赖）
> 测试环境：**MySQL 8.0.12 / Windows 7 SP1 / 库名 dsh_memory**（10.0.0.1）
> 结论先放前面：**"记忆读写"这条线完整可用；"会话导入（sync）"还没移植 —— 建议先发 beta，或补齐 sync 再发正式版。**

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
| `handoff` | ⚠ 未测 | 需要跨机会话数据；逻辑只读 messages |
| `prune` | ⚠ 未测 | 会删历史归档，属不可逆操作，**没有在测试库上跑** |
| `embed` / `recall` | ⚠ 未测 | 需要配置 `embed` 块（语义检索，可选功能） |
| `sync` | ❌ **未移植** | 解压环节 OK（2 帧/0 坏帧），写库环节失败：SQL Server 侧用的是 `SqlBulkCopy`，MySQL 没有等价物 |

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

## 四、已知限制（照实写）

```
· sync 未移植（最大的一个）：会话日志暂时导不进 MySQL 库
  → 直接影响："记住全部对话"这条能力用不了；save/search/replica/backup 不受影响
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
mysql -uroot -p -e "CREATE DATABASE dsh_memory CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"
for f in sql/mysql/0*.sql; do mysql --defaults-extra-file=my.cnf --init-command="SET time_zone='+00:00'" dsh_memory < "$f"; done

# 配置里 provider=mysql + mysqlCliPath 指向 mysql.exe
powershell -File memory\dsh-mem.ps1 save -Title 测试 -Body 你好 -Scope global
powershell -File memory\dsh-mem.ps1 search 测试
powershell -File memory\dsh-mem.ps1 stats
powershell -File memory\dsh-mem.ps1 backup
node memory\plugin\verify.mjs        # 端到端注入自检，应 RESULT: PASS
```
