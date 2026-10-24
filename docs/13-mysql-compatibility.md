# MySQL / MariaDB 版本兼容说明

> 一句话：**MySQL 5.6.4 及以上可用**；推荐 5.7 或 8.0；**实测环境是 8.0.12**。
> MariaDB 10.2+ 理论可用（SIGNAL/触发器/ODKU 都支持），但我们**没有实测**，请自行验证。

## 一、版本矩阵

| 版本 | 状态 | 说明 |
|---|---|---|
| **8.0.x** | ✅ 实测通过（8.0.12） | 本项目的基准环境 |
| **5.7.x** | 🟡 **建库 + 基础命令已实测**（5.7.26，2026-10-24） | 建库脚本 10 表/6 触发器全过；version/save/search/stats/roster/recent 通过；backup/sync/prune 因测试机实例不稳定**未完成** |
| **5.6.4–5.6.x** | 🟡 理论可用（未实测） | 需要 DATETIME(3)（5.6.4+）；老版本注意 `sql_mode` 更严格 |
| **5.5 及更早** | ❌ 不行 | 没有 `DATETIME(3)` 小数秒 |
| **8.1–8.3** | 🟡 应当可用 | 与 8.0 基本一致 |
| **8.4+** | ⚠️ 需要改一处 | `mysql_native_password` 默认**禁用**；建账号别指定该插件 |
| **MariaDB 10.2+** | 🟡 未实测 | 语法基本兼容；`SIGNAL`、ODKU、临时表都支持 |
| **MariaDB 10.1 及更早** | ❌ 不建议 | 部分语法差异 |

> 5.7 实测补充（2026-10-24）：`sql/mysql/001..007` 在 **MySQL 5.7.26** 上全部执行成功
> （10 张表、6 个只追加触发器、`utf8mb4_general_ci`）；引擎基础命令可用。
> 长跑类命令（`backup` / `sync` / `prune`）在本次测试里因临时实例反复掉线未跑完，
> **不写"通过"** —— 需要时请在稳定实例上补测。

## 二、我们实际用到的特性与最低版本

```
DATETIME(3) / CURRENT_TIMESTAMP(3)   5.6.4+ / 5.6.5+
SIGNAL SQLSTATE（触发器拦 UPDATE）   5.5+
BEFORE UPDATE/DELETE 触发器          5.0+
INSERT ... ON DUPLICATE KEY UPDATE   很早就有
CREATE TEMPORARY TABLE               很早就有
utf8mb4                              5.5.3+
utf8mb4_0900_ai_ci（仅在文档里出现过）**仅 8.0+** ← 已改成 general_ci
mysql_native_password 认证插件       8.4 起默认禁用
mysqldump --set-gtid-purged=OFF      5.6+
VALUES(col) 在 ODKU 里               已弃用（8.0.20+ 告警），仍可用；未来大版本可能移除
```

## 三、不同版本要改的地方（照做即可）

### 1) 建库的排序规则

```sql
-- 5.6 / 5.7 / 8.0 / MariaDB 通用
CREATE DATABASE dsh_memory CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- 只在 8.0+ 才有（不要用，跨版本会失败）
-- utf8mb4_0900_ai_ci
```

### 2) 建账号的认证插件

```sql
-- ≤ 8.3
CREATE USER 'dsh'@'%' IDENTIFIED WITH mysql_native_password BY '强口令';

-- 8.4+（该插件默认禁用；让它用默认的 caching_sha2_password）
CREATE USER 'dsh'@'%' IDENTIFIED BY '强口令';
```

> 客户端（`mysql.exe`）版本与服务器不一致一般没问题；但 **8.4 服务器 + 老客户端**可能因认证插件不匹配报错，
> 那种情况用与服务器同版本或更新的客户端。

### 3) 触发器权限

任何版本都一样：开了 binlog 时建触发器需要 SUPER 或

```sql
SET GLOBAL log_bin_trust_function_creators = 1;   -- 建完可以再关掉
```

## 四、自查命令

```bash
mysql -uroot -p -e "SELECT VERSION(); SELECT @@version_comment;"
mysql -uroot -p -e "SHOW VARIABLES LIKE 'log_bin_trust_function_creators';"
mysql -uroot -p -e "SELECT @@character_set_server, @@collation_server;"
```

引擎侧：`dsh-mem.ps1 stats` 能连通即说明版本能力够用；
若服务器 < 5.6.4，引擎会打印一行警告（不阻断）。
