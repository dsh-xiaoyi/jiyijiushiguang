# 配置文件字段说明（dsh-mem.config.json）

> 引擎、插件、同步任务都读这一份。默认放 `C:\dsh-mem\dsh-mem.config.json`
> （也可用 `-Root <目录>` 或环境变量 `DSH_MEM_CONFIG` 指定）。

| 字段 | 必填 | 说明 |
|---|---|---|
| `server` | 是 | SQL Server 地址：`127.0.0.1,1433` 或 `127.0.0.1\SQLEXPRESS` |
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
