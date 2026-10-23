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
| **SQLite** | ⏳ 计划中（单独版本） | 单机用户：零安装、零授权、一个文件 |
| **MySQL** | ⏳ 计划中（单独版本） | 多机共享记忆、但又没有 SQL Server 授权的人 |

> 我们自己的舰队仍跑 SQL Server，不切换；SQLite/MySQL 会作为**独立版本**开发、测试通过后再发布。
> 这样每个版本都能"下载就能用"，而不是让用户自己改连接字符串和方言。

## 边界（说清楚，避免误解）

- 记忆库里的**数据不随仓库发布**；仓库只有代码、结构与模板。
- 这是 `v0.1.0`（experimental）：接口可能变，重要环境请先备份。
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

MIT。作者：**小易**。

---

## 致谢

这套东西起于一个很朴素的问题：**"你怎么又忘了？"**
如果你也在解决同一类问题，希望这里踩过的坑能帮你少走几步。
