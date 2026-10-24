# 记忆旧时光（jiyijiushiguang）

> **让 DSH 记住你们定过的约定。** 会话再长，也不用重新解释一遍。

一个最小可用的长期记忆层：把对话与决定存进**你自己的数据库**，并在每次会话开局，
把「该记得的东西」自动放到模型眼前 —— 而不是指望它恰好没被上下文截断。

> 第一次读到这里，不必一次记住；先照着跑一遍，遇到问题再回来查对应那一节。

---

## 它解决什么问题

单个 DSH 聊久了会开始"忘记"：昨天定过的规则、上周踩过的坑、你反复纠正的那几条。
这不是模型变笨，是**每次会话只看得到最近一小段上下文**，而那段里没有你们定过的东西。

本项目做三件事：

1. **存**：会话、消息、决定、教训都进数据库（可追溯、可回滚、可备份）
2. **取**：按关键词 + IDF（稀有词加权）检索，不用语义模型也能答到点上
3. **放**：每轮会话自动注入「强制指令 + 相关旧记忆 + 关键约定全文 + 定义型记忆」

## 环境要求

```
PowerShell 5.1+（Windows 10 / 11 / Server 2016 及以上系统自带）
Node.js（只有注入插件需要）
SQL Server（Express 免费版即可）—— 建表时需要一次 sysadmin
Windows 7 用户：需先装 WMF 5.1（系统自带的是 PowerShell 2.0），否则脚本无法运行
```

## 5 分钟跑起来（Windows + SQL Server）

```powershell
# 0) 前置：Windows + PowerShell 5.1+ + SQL Server（Express 免费版即可）

# 1) 复制配置并改连接串
mkdir C:\dsh-mem
Copy-Item examples\config.example.json C:\dsh-mem\dsh-mem.config.json
notepad C:\dsh-mem\dsh-mem.config.json

# 2) 建库建表（需要 SQL sysadmin，一次性）
#    先建库：CREATE DATABASE DSHMemory;
foreach ($f in Get-ChildItem sql\sqlserver\*.sql | Sort-Object Name) {
    sqlcmd -E -d DSHMemory -i $f.FullName
}

# 3) 装注入插件（这一步才是"记忆真的进到会话里"的关键）
$pd = Join-Path $env:USERPROFILE '.dsh\profiles\desktop'
New-Item -ItemType Directory -Path (Join-Path $pd 'node_modules') -Force | Out-Null
cmd /c mklink /D "$pd\node_modules\dsh-memory-bridge" "$PWD\memory\plugin"
#    然后在 $pd\package.json 的 dependencies 里加一行：
#      "dsh-memory-bridge": "link:<仓库路径>\memory\plugin"
#    ★ 重启 DSH（不重启 = 插件不加载，而且不会报错，最容易被忽略）

# 4) 体检
powershell -File ops\doctor.ps1 -ConfigPath C:\dsh-mem\dsh-mem.config.json

# 5) 存一条、再搜回来
powershell -File memory\dsh-mem.ps1 save -Title "第一条记忆" -Body "你好" -Scope global
powershell -File memory\dsh-mem.ps1 search 记忆
```

跑通之后，下一次会话你应该能看到注入段落里出现「关键约定」与「自动检索」。


## 记忆是怎么"保持新鲜"的（重要）

注入插件读的是一份**离线副本**（JSON），不是每次都查库。所以刷新机制必须有人负责：

`
方式 A（推荐，开箱即用）：ops\install.ps1 -RegisterTasks
  → 注册两个计划任务：DSH_MemReplica（每 1 分钟导出副本）、DSH_MemSync（每 3 分钟导入新会话）

方式 B（不注册任务也行）：插件会在副本过期（默认 180 秒）时**自己在后台触发一次刷新**
  → 效果略慢一拍，但零配置
`

> 本仓库**不包含**任何常驻服务/闭源程序：刷新要么靠计划任务，要么靠插件自触发，二选一即可。

## MySQL 版怎么装（v0.2.0 · 建表已验证）

```
版本要求：MySQL 5.6.4+（推荐 5.7 / 8.0；8.4+ 见下方"认证插件"一行）
实测环境：MySQL 8.0.12 / Windows。MariaDB 理论可用但未测。
细节见 docs/13-mysql-compatibility.md
```

```bash
# 1) 建库（utf8mb4 必须显式）
mysql -uroot -p -e "CREATE DATABASE dsh_memory CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

# 2) 建账号（只给这个库的权限）
#    认证插件按你的版本选：≤8.3 用 mysql_native_password；8.4+ 默认禁用该插件，去掉 IDENTIFIED WITH 让它用默认插件
mysql -uroot -p -e "CREATE USER 'dsh'@'%' IDENTIFIED WITH mysql_native_password BY '你的强口令';
                    GRANT ALL PRIVILEGES ON dsh_memory.* TO 'dsh'@'%'; FLUSH PRIVILEGES;"

# 3) 建表（按编号执行；连接时把会话时区设为 UTC）
for f in sql/mysql/0*.sql; do
  mysql --defaults-extra-file=my.cnf --init-command="SET time_zone='+00:00'" dsh_memory < "$f"
done

# 4) 验收
mysql --defaults-extra-file=my.cnf -t dsh_memory < sql/mysql/009-verify.sql
```

> ⚠ 安全：账号、端口、备份、字符集这几件事请先看 [docs/12-mysql-security](docs/12-mysql-security.md)。
> SQLite 版的边界更物理（文件权限就是全部安全边界），见 [docs/14-sqlite](docs/14-sqlite.md)。

实测环境：**MySQL 8.0.12（Windows）**，10 张表 + 6 个只追加触发器全部建成；
`UPDATE/DELETE messages` 会被触发器拦住（SQLSTATE 45000），`UPDATE memories` 正常放行。

## 目录

```
memory\     引擎（dsh-mem.ps1）+ 注入插件（plugin\）+ 约定模板（conventions.example.md）
sql\        建表脚本，按数据库分目录：sqlserver\（现在）· sqlite\（计划）· mysql\（计划）
ops\        install.ps1（一键装）/ doctor.ps1（体检）/ secret-scan.ps1（发布前扫描）
examples\   config.example.json（占位值）
docs\       为什么做 / 记忆设计（含三层缺陷复盘）/ 复盘集 / 权限与安全软件
```

## 数据库支持（重要）

| 数据库 | 状态 | 适合谁 |
|---|---|---|
| **SQL Server** | ✅ 本仓库当前版本 | 已有 SQL Server 授权的人 |
| **MySQL** | ✅ v0.2.0 已支持（10 表 + 6 触发器 + sync/备份全部实测） | 多机共享、又不想买 SQL Server 授权的人 |
| **SQLite** | ⏳ 计划中（v0.3.0） | 单机用户：零安装、零授权、一个文件 |


> 我们自己的集群仍跑 SQL Server，不切换；SQLite/MySQL 会作为**独立版本**开发、测试通过后再发布。
> 这样每个版本都能"下载就能用"，而不是让用户自己改连接字符串和方言。

## 边界（说清楚，避免误解）

- 记忆库里的**数据不随仓库发布**；仓库只有代码、结构与模板。
- 这是 `v0.2.2`（experimental）：接口可能变，重要环境请先备份。
- 检索是关键词 + IDF，不是语义向量（向量表已留好，后续可接）。

## 权限与安全软件

装不动、或被杀软拦？看 [docs/08-permissions-and-antivirus](docs/08-permissions-and-antivirus.md)：
里面列了每一步需要什么权限（建表 sysadmin、插件要 profile 写权限…），
以及 360 / Defender 常见拦截点与"加白名单而不是关防护"的做法。

## 文档

| 文件 | 内容 |
|---|---|
| [docs/00-why](docs/00-why.md) | 我们为什么做这个（含三次失败） |
| [docs/02-memory-design](docs/02-memory-design.md) | 注入四段、为什么必须 IDF、三层缺陷复盘 |
| [docs/04-postmortems](docs/04-postmortems.md) | 真实事故与修法 |
| [docs/08-permissions-and-antivirus](docs/08-permissions-and-antivirus.md) | 权限要求 + 安全软件拦截 |
| [docs/ROADMAP](docs/ROADMAP.md) | 接下来做什么（SQLite / MySQL / 向量检索） |
| [docs/09-file-map](docs/09-file-map.md) | 每个文件是干什么的 |

## 许可与署名

MIT。作者：**小易** <img src="assets/blue-fish.jpg" width="56" alt="蓝色大肥鱼" title="蓝色大肥鱼（DeepSeek）">

---

## 致谢

这套东西起于一个很朴素的问题：**"你怎么又忘了？"**
如果你也在解决同一类问题，希望这里踩过的坑能帮你少走几步。
