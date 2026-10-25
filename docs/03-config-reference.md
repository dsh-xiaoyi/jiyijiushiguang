# 配置文件字段说明（dsh-mem.config.json）

> 引擎、插件、同步任务都读这一份。默认放 `C:\dsh-mem\dsh-mem.config.json`
> （也可用 `-Root <目录>` 或环境变量 `DSH_MEM_CONFIG` 指定）。

| 字段 | 必填 | 说明 |
|---|---|---|
| `provider` | 否 | `sqlserver`（默认）或 `mysql` |
| `server` | 是 | sqlserver：`127.0.0.1,1433` 或 `127.0.0.1\SQLEXPRESS`；mysql：`主机,端口` |
| `mysqlCliPath` | 否 | mysql 客户端路径（默认走 PATH 里的 `mysql`）；Win 上一般是 `...\MySQL Server 8.0\bin\mysql.exe` |
| `database` | 是 | 数据库名，默认 `DSHMemory` |
| `user` / `password` | 否 | SQL 登录（建议单独建低权限账号）；留空 = Windows 集成认证 |
| `sessionsRoot` | 是 | DSH 会话目录，Windows 一般 `%USERPROFILE%\.dsh\sessions`；`sync` 从这里导入 |
| `node` | 否 | 指定 node.exe 路径（插件后台刷新用） |
| `replicaPath` | 否 | 离线副本路径；默认 `<配置目录>\dsh-mem-replica.json` |
| `cliPath` | 否 | 引擎路径；默认 `<配置目录>\dsh-mem.ps1` |
| `replicaMaxAgeSeconds` | 否 | 副本多久算过期（默认 180 秒），过期时插件会后台触发刷新 |
| `redact` | 否 | 脱敏词表（空格分隔）：入库/出副本前替换掉，防口令进明文 |
| `embed` | 否 | 语义检索（可选）：`{ baseURL, model }`；不配就只用关键词 + IDF |

## 最小可跑配置

```json
{
  "server": "127.0.0.1,1433",
  "database": "DSHMemory",
  "user": "dsh_app",
  "password": "EXAMPLE_PASSWORD",
  "sessionsRoot": "C:\\Users\\YOURNAME\\.dsh\\sessions"
}
```

## 安全建议

```
· 日常运行用低权限账号（只对 DSHMemory 有 db_datareader/db_datawriter）；建表时才用 sysadmin
· 口令不要写进脚本/聊天/日志；配置文件 ACL 收紧到当前用户
· redact 里至少放：数据库口令、桥令牌、任何不想入库的字符串
```

## MySQL 后端（provider = mysql）

```json
{
  "provider": "mysql",
  "server": "127.0.0.1,3306",
  "database": "dsh_memory",
  "user": "dsh",
  "password": "EXAMPLE_PASSWORD",
  "sessionsRoot": "C:\\Users\\YOURNAME\\.dsh\\sessions",
  "mysqlCliPath": "C:\\Program Files\\MySQL\\MySQL Server 8.0\\bin\\mysql.exe",
  "replicaPath": "C:\\dsh-mem\\dsh-mem-replica.json"
}
```

要点：

```
· 引擎通过 **mysql.exe** 执行 SQL（不依赖任何 DLL），所以 mysql 客户端必须在 PATH 或 mysqlCliPath 里
· 每次查询都是一次新的进程/连接：因此 INSERT 与 LAST_INSERT_ID() 必须在同一次调用里（引擎已处理）
· 时间统一 UTC：引擎每次调用都会带 --init-command=SET time_zone='+00:00'
· 建表脚本在 sql/mysql/，建表前先跑 007-append-only.sql 需要的权限说明见该文件头部
```

## state / anchor（0.5.1 新增）

| 键 | 默认值 | 说明 |
|---|---|---|
| `stateDir` | `C:\dsh-mem\sessions` | 会话状态文件所在目录；目录不存在则跳过该段 |
| `stateCards` | `3` | 最多注入几张状态卡（按最近更新排序） |
| `stateMaxChars` | `2400` | `state` 段字符上限 |
| `anchorPath` | `C:\dsh-mem\anchors\LATEST.md` | 锚点清单文件；文件不存在则跳过该段 |
| `anchorMaxChars` | `900` | `anchor` 段字符上限 |

> 两段都受全局预算缩放（`budgetScale`）与下限（`BUDGET_FLOOR`）约束；
> 段被截断时会在注入内容里显式标注省略数量，不静默丢弃。