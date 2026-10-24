# SQLite 版：安装、配置与限制

> 一句话：**单机场景最省事** —— 一个文件就是整个记忆库，不用装数据库、不用开端口、不用授权。
> 代价是：**不能多机共享**（文件只有一份），并发写入是单写者。

## 一、版本要求

```
sqlite3 CLI 3.33 及以上（引擎用 -json 输出解析结果；实测 3.50.4）
下载：https://www.sqlite.org/download.html → sqlite-tools-win-x64-*.zip（约 6MB，只有一个 exe）
```

引擎**不内置** sqlite3.exe（和 mysql 后端一样走外部 CLI，零 DLL 依赖），放哪都行，配置里写绝对路径。

## 二、配置（dsh-mem.config.json）

```json
{
  "provider": "sqlite",
  "sqliteDb": "C:\\dsh-mem\\data\\dsh-mem.db",
  "sqliteCliPath": "C:\\dsh-mem\\tools\\sqlite\\sqlite3.exe",
  "replicaPath": "C:\\dsh-mem\\data\\replica.json",
  "sessionsRoot": "C:\\dsh-mem\\sessions"
}
```

## 三、建库（一次性）

```powershell
$sql = "C:\path\to\sql\sqlite"
$db  = "C:\dsh-mem\data\dsh-mem.db"
$cli = "C:\dsh-mem\tools\sqlite\sqlite3.exe"
New-Item -ItemType Directory -Force (Split-Path $db) | Out-Null
foreach ($f in '001-core-tables.sql','002-artifacts.sql','003-embeddings.sql','004-credentials.sql',
               '005-lesson-records.sql','006-llm-retries.sql','007-append-only.sql') {
  & $cli $db ".read $sql\$f"
}
& $cli $db ".read $sql\009-verify.sql"
```

自检应看到：表 10 / 触发器 6 / 索引 12 / allow_mutation 0 / journal wal。

> 001 开头会 `PRAGMA journal_mode = WAL`：读写并发更好，但会多出 -wal / -shm 两个伴随文件，
> **备份时用 `.backup`，不要直接拷正在写的 .db**。

## 四、常用命令

```
dsh-mem.ps1 version / save / search / recent / history / secrets / stats / roster /
            replica / backup / sync / prune / handoff / recall
```

backup 走 SQLite 的 `.backup`（在线备份，WAL 下也一致），同时照旧导出 memories-backup-*.json。

## 五、与另两个后端的差异（只列会影响行为的）

| 项目 | SQL Server | MySQL | SQLite |
|---|---|---|---|
| 时间类型 | datetime2(3) | DATETIME(3) | **TEXT**（ISO8601 UTC 带毫秒） |
| 只追加保护 | DENY UPDATE/DELETE（权限） | 触发器 6 个 | 触发器 6 个 + _guard_state 维护开关 |
| 批量导入 | SqlBulkCopy | 临时表 + 行级 upsert | 临时表 + 行级 upsert（一次 CLI 调用） |
| 备份 | BACKUP DATABASE | mysqldump | .backup |
| 多机共享 | 可以 | 可以 | **不行（单文件）** |
| 并发写 | 可以 | 可以 | 单写者（WAL 下读不阻塞） |

## 六、只追加怎么保证（SQLite 没有权限这回事）

```
库文件权限 = 全部安全边界：能给文件写权限的人，等于能手改数据。
所以「消息/归档/教训不许改、不许删」改成触发器拦：
  BEFORE UPDATE/DELETE ... WHEN (SELECT val FROM _guard_state WHERE key='allow_mutation') = 0
  BEGIN SELECT RAISE(ABORT, '... is append-only: ...'); END;
维护模式（sync / prune 需要）：同一连接里
  UPDATE _guard_state SET val = 1 WHERE key = 'allow_mutation';
  ... 维护操作 ...
  UPDATE _guard_state SET val = 0 WHERE key = 'allow_mutation';
  （引擎把三步放进同一个 CLI 调用和同一个事务，失败整体回滚）
```

## 七、安全（SQLite 的边界更物理）

```
· .db 文件里就是明文记忆（含 kind=secret 的凭据）⇒ 必须收紧文件 ACL：
    只留 SYSTEM + 管理员组；别放共享目录、别放同步盘、别进 git
· 备份文件（.db / json）同样是明文 ⇒ 加密存放，或随加密包一起走
· 备份请用 .backup 或 VACUUM INTO，不要热拷正在写的 .db
· 没有账号/密码这层网：能读文件的人就能读全部记忆 —— 这是最需要留意的一点
```

## 八、已知限制

```
· 不能多机共享同一个库（要共享请用 MySQL / SQL Server）
· 并发写入单写者：多智能体同时高频写会排队
· embed / recall 的语义检索需要模型端点；没配时 recall 会明确降级为字面检索
· handoff / prune 已实测通过（prune 适配了只追加触发器）
```

## 版本来源与可信度（2026-10-24 新增）

写兼容性结论前，先看"这个版本号是怎么来的"。**自报 ≠ 事实**。

| 版本信息 | 值 | 来源 | 可信度 |
|---|---|---|---|
| MySQL 8.0.x | **8.0.12** | `SELECT VERSION()` 实查（11 带凭据，2026-10-24） | ✅ 已验证 |
| MySQL 5.7.x | **5.7.26** | `SELECT VERSION()` 实查（测试机 3307） | ✅ 已验证 |
| SQLite | 要求 **CLI ≥ 3.33**；实测客户端 **3.50.4** | `sqlite3 --version`（11 测试机，test-only） | ✅ 已验证（仅客户端） |
| 外部反馈：MySQL banner | 8.0.12 | 18 号机握手自报（无凭据，未查询） | ⚠️ 未验证，不作依据 |
| 外部反馈：SQLite 3.53.1 | 3.53.1 | 18 号机自带 Python 的 sqlite3 | ⚠️ 与目标机无关，**不是环境要求** |

两条纪律：
1. **banner / 客户端握手** 只是服务端自报，写进对外文档前必须标注来源，或补一次实查。
2. **工具链自带版本**（如 Python 内置 sqlite3）不等于目标机要求，不得写成"本项目要求 X"。
### MySQL 升级提示（v0.3.8）

`messages` 现在有 `UNIQUE KEY UQ_messages_sess (session_id, seq)`（与 SQLite 对齐）。
**已有库需要手工加索引**（新装由 `sql/mysql/001` 自动建）：

```sql
-- 先确认没有重复行（有重复会失败，必须先处理）
SELECT session_id, seq, COUNT(*) FROM messages GROUP BY session_id, seq HAVING COUNT(*) > 1;
-- 无重复时执行
ALTER TABLE messages ADD UNIQUE KEY UQ_messages_sess (session_id, seq);
```