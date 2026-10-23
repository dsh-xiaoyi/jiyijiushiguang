# 洁净机器安装演练（发布前必做）

> 目的：验证"一个陌生人，照 README 跑，能不能跑通"。
> 判据：**每一步都有可复核输出**；失败要能说出为什么，不能"再试试"。

## 测试机前置

```
Windows 10/11 或 Server 2019+
PowerShell 5.1+（系统自带即可）
SQL Server（Express 免费版即可）—— 装的时候注意：
  · 实例名：默认实例 或 SQLEXPRESS（连接串要对应，例如 127.0.0.1,1433 或 .\SQLEXPRESS）
  · 混合模式认证 + 记住 sa 密码（或只用 Windows 认证）
  · 防火墙：仅内网需要时放行 1433
Node.js（注入插件运行需要）
安全软件：把本仓库目录加入信任区（见 docs/08）
```

## 步骤与判据

| # | 动作 | 通过判据 |
|---|---|---|
| 1 | `git clone <仓库>` 到任意路径 | 目录里有 README / memory / sql / ops |
| 2 | 复制配置：`Copy-Item examples\config.example.json C:\dsh-mem\dsh-mem.config.json` | 文件存在，且里面没有 `EXAMPLE_PASSWORD`（已改成真口令） |
| 3 | 建库：`sqlcmd -E -S <实例> -Q "CREATE DATABASE DSHMemory"` | 命令 exit=0 |
| 4 | 建表：逐个执行 `sql\sqlserver\*.sql` | 每个脚本 exit=0；无 "已存在" 报错（第一次装） |
| 5 | 体检：`ops\doctor.ps1 -ConfigPath ...` | 打印 `RESULT: PASS`；DB 可连接、副本新鲜 |
| 6 | 存一条：`memory\dsh-mem.ps1 save -Title "第一条记忆" -Body "你好" -Scope global` | 输出保存成功，且有 id |
| 7 | 搜回来：`memory\dsh-mem.ps1 search 记忆` | 能搜到刚刚那条（标题/正文出现） |
| 8 | 装插件：`mklink /D` 到 profile 的 node_modules + 改 package.json 依赖 | 链接存在；DSH 重启后无报错 |
| 9 | **重启 DSH** | 新会话里出现「关键约定」与「自动检索」两段（行为判据，不是看配置） |
| 10 | 回归：隔一天再开新会话，问一句以前定过的事 | 能直接答对，不需要你重复解释 |

## 常见失败与定位

| 现象 | 先看哪里 |
|---|---|
| `doctor.ps1` 报数据库连不上 | 实例名/端口是否正确（`127.0.0.1,1433` vs `.\SQLEXPRESS`）、是否启用 TCP、防火墙 |
| SQL 脚本报"已存在" | 你跑第二遍；第一遍应该全绿 |
| 插件装了但注入没变化 | **有没有重启 DSH**（最常见）；再看 `doctor.ps1` 的插件检查 |
| 杀软弹窗/静默拦截 | 把仓库目录加信任区；不要关防护（见 docs/08） |
| 中文乱码 | `.ps1` 必须是 UTF-8 **带 BOM**；用 `powershell -File` 而不是双击 |

## 记录模板（每次演练填一份）

```
日期 / 测试机 / Windows 版本 / SQL 版本 / Node 版本
1-10 步：每步 PASS 或 FAIL + 证据（命令输出关键行）
结论：可发布 / 需修复（列出问题单）
```
