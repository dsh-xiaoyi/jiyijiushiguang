# 长期运行说明（能不能一直用、要注意什么）

> 这一页是给"打算长期用"的人看的。结论先说：**核心功能可以长期用**，
> 但有几条前提必须满足，另外有一两项**还没验证过**，用之前请自己先跑一次。

## 一、三档结论

### ✅ 可以放心长期跑

| 项 | 依据 |
|---|---|
| SQL Server 后端 | 生产环境连续使用多周（每日 03:30 备份、注入、队列） |
| MySQL 8.0.12 后端 | 15 命令实测 + 幂等 + 只追加 + 备份完整 |
| MySQL 5.7.26 后端 | 完整验收（建库 / 15 命令 / 267 行导入 / 幂等 / dump 10 表 6 触发器） |
| SQLite 后端 | 同上（10 表 6 触发器、267 行、幂等、`.backup`、只追加） |
| 核心命令 | `save` `search` `recent` `history` `secrets` `stats` `roster` `replica` `backup` `sync` `prune` `handoff` `recall` |

### ⚠️ 能用，但有前提

```
embed（语义检索）      未测。需要本地模型端点（bge-m3 等）。用前先跑：embed -Limit 5
MySQL 5.6.x           理论可用，未实测
MySQL 8.4+            认证插件默认改了（mysql_native_password 被禁用），按 docs/12 建账号
MariaDB               未实测
sync 的解压器          需要 Node 22.15+/23+；缺了会明确报错并 exit 1（v0.3.3 起）
SQLite 单文件          不能多机共享；并发写单写者；库文件即明文 → 必须收紧 ACL
每次命令都起一个客户端进程（约 50-100ms）→ 适合人用，不适合高频批量
```

### ❌ 不要用

```
v0.3.0 / v0.3.1    SQL Server / MySQL 配置启动即崩（release 正文里有警告）
v0.2.x 之前        没有 SQLite，也缺 5.7 / prune / 安全 相关修复
```

## 二、长期运行的几条纪律

```
① 锁版本：钉在 v0.3.3（或之后明确验证过的版本），不要跟着 main 走
② 定期自查：用 docs/15-verification-checklist.md，每月一次
   重点三条：machines 行数 ≥ 1 ／ COUNT(*) 与 COUNT(DISTINCT session_id,seq) 相等 ／ save 的 readback 左右相等
③ 备份不变：每日本地 + 每周加密包 + 冷备；SQLite 用 .backup 而不是热拷 .db
④ 客户端版本匹配服务器：MySQL 8.0 的 mysqldump 去 dump 5.7 需要 --column-statistics=0（引擎已处理）
⑤ 日志要看：把 backup / sync 的输出留档 —— "成功"要看数字，不看返回码
```

## 三、性能与容量（给做规划的）

```
单机 SQLite：几万条记忆/消息无压力；单写者，写入排队
MySQL 5.7/8.0：几千到几百万行都行，取决于实例配置（小机器把 innodb_buffer_pool_size 调到 128M~256M）
SQL Server：本项目的基准环境
每次命令一次进程启动 + 一次连接：几十毫秒级；每秒几十次的批量场景请直接写库或走常驻连接
```

## 四、还没验证的（诚实列表）

```
· embed 真实嵌入（需要模型端点）
· MySQL 5.6.x / MariaDB / MySQL 8.4+
· 长时间浸泡（连续数周无人工干预）
· 多实例并发写同一个 MySQL（只测了单机顺序调用）
```

## 五、如果你的环境是"小机器"

```
· 2 核 4G 足够跑 SQLite 后端与测试用 MySQL
· 同机还跑 Web/PHP 时，把 MySQL 的 innodb_buffer_pool_size 降到 128M~256M
· 不要同时起两个 MySQL 实例去抢内存（本项目不需要）
```
