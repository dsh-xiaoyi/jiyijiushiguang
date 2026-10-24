# 验收自查清单（独立断言）

> 为什么需要这一页：**引擎说"OK"不算证据**。
> 2026-10-24 复核 SQLite 时发现：`Register-Host` 静默写 0 行，`save`/`sync` 全都返回成功，
> 但 `roster` 永远显示 0 台机器。只有**直接查库**才能抓到这类失败。
>
> 所以验收的统一做法是：引擎输出 + **你自己用数据库客户端再数一遍**。

## 一、通用：数行数（三个后端命令不同，判断标准相同）

```sql
-- 期望：memories ≥ 1（你存过至少一条）
SELECT COUNT(*) AS memories FROM memories;
-- 期望：messages 数量 == 导入的会话事件数，且没有重复
SELECT COUNT(*) AS messages, COUNT(DISTINCT session_id || '/' || seq) AS uniq FROM messages;
-- 期望：sessions 等于你导入过的会话数
SELECT COUNT(*) AS sessions FROM sessions;
-- 期望：machines ≥ 1（跑过 save/sync/replica/backup 之后必须出现本机）
SELECT login_name, machine, cli_version, last_seen FROM machines;
```

各后端怎么执行：

```powershell
# SQL Server（应用账号即可，不需要 sysadmin）
sqlcmd -S <host>,1433 -d DSHMemory -U <user> -P <pwd> -Q "SELECT COUNT(*) FROM dbo.machines"

# MySQL
mysql --defaults-extra-file=<临时选项文件> dsh_memory -e "SELECT COUNT(*) FROM machines"

# SQLite
sqlite3 C:\dsh-mem\data\dsh-mem.db "SELECT COUNT(*) FROM machines"
```

> 建议把口令写进临时选项文件（`[client]` 段），**不要**用 `-p口令` 放在命令行上。

## 二、只追加保护（三个后端都要验这一条）

```powershell
# 先插一条测试行（INSERT 允许）
# SQLite
sqlite3 dsh-mem.db "INSERT INTO messages (session_id,seq,role,text) VALUES ('t',1,'user','x')"
# 再试图改它（应该被拦）
sqlite3 dsh-mem.db "UPDATE messages SET role='y' WHERE session_id='t'"
# 期望：Runtime error: messages is append-only: UPDATE is not allowed
```

```
SQL Server  期望：UPDATE 被 DENY（错误 229 / 权限被拒）
MySQL       期望：ERROR 1644 (45000) messages is append-only
SQLite      期望：Runtime error: messages is append-only
```

维护模式（只有 `sync` / `prune` 用，正常使用**不要**开）：

```
MySQL   SET @dsh_allow_mutation = 1;   -- 同一连接内有效
SQLite  UPDATE _guard_state SET val = 1 WHERE key='allow_mutation';   -- 用完立刻改回 0
```

## 三、写入是否真的落地（`save` 的复核）

```
期望输出里有两行：
  saved memory id=<数字>
  readback : title <n>/<n> chars, body <n>/<n> chars
左右两个数字必须相等。不相等 = 被截断或脱敏改写了内容。
```

## 四、`sync` 是否幂等（重复导入不产生重复行）

```powershell
dsh-mem.ps1 sync -All -Force     # 第二次跑同一条命令
# 期望：inserted=0  updated=0  removed=0
```

再配合第一节的 SQL：`COUNT(*)` 与 `COUNT(DISTINCT session_id||'/'||seq)` 必须相等。
MySQL 语法用 `COUNT(DISTINCT CONCAT(session_id,'/',seq))`。

## 五、备份是否可用（不只看"命令成功"）

```
① 备份文件存在且大小 > 0
② SQLite 用 .backup（不要热拷 .db）；MySQL 用 mysqldump；SQL Server 用 BACKUP DATABASE
③ 抽一天做一次"恢复验证"：把备份还原到临时库，数一次 memories 行数
```

## 六、`roster` 必须显示本机（最常见的静默失败）

```
症状：save / sync 都成功，roster 却显示 0 台机器
原因：注册本机的那一步失败却被 catch 吞掉了
判断：直接查 machines 表（第一节最后那条 SQL）
修复参考：v0.3.1（SQLite 后端曾因此静默写 0 行）
```

## 七、一张表总结

| 要验的事 | 命令 | 期望 |
|---|---|---|
| 库里有数据 | 各后端 COUNT(*) | memories ≥ 1 |
| 会话导入没重复 | COUNT vs COUNT(DISTINCT) | 两个数相等 |
| 本机已登记 | SELECT * FROM machines | ≥ 1 行，cli_version 有值 |
| 只追加生效 | 手动 UPDATE | 被拒 |
| 写入未截断 | save 的 readback | 左边 = 右边 |
| 重复导入幂等 | sync -Force 二次 | inserted=0 |
| 备份真的存在 | 看备份目录 | 文件 > 0 字节 |
