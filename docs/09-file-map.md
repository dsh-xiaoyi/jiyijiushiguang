# 文件地图（每个文件是干什么的）

> 第一次看仓库时先看这一页，比逐个点开快。

## 根目录

| 文件 | 作用 |
|---|---|
| `README.md` | 门面：解决什么问题 + 5 分钟跑起来 |
| `LICENSE` | MIT |
| `CHANGELOG.md` | 版本变更 |
| `.gitignore` | 凭据、日志、数据导出一律不进仓库 |

## `memory/` —— 记忆引擎与插件

| 文件 | 作用 |
|---|---|
| `dsh-mem.ps1` | 引擎 CLI：save / search / recent / sync / backup / replica / history |
| `mem-artifact.ps1` | 把文件登记成"工件"（入库 + 哈希校验） |
| `conventions.example.md` | 关键约定模板（复制成 `conventions.md` 再按自己情况改） |
| `dsh-zstd-extract.js` | 会话日志解压（DSH 用多帧 zstd；需 Node 22.15+/23+） |
| `plugin/index.mjs` | 注入插件：每轮把"强制指令 + 相关旧记忆 + 关键约定 + 定义型记忆"放进上下文 |
| `plugin/verify.mjs` | 插件自检：副本路径、注入是否真的发生 |
| `plugin/package.json` / `cordis.patch.yml` | 插件声明与 DSH 配置片段 |

## `sql/` —— 建表脚本

| 目录 | 状态 |
|---|---|
| `sql/sqlserver/` | ✅ 当前版本（13 个脚本，按编号执行） |
| `sql/sqlite/` | ⏳ 计划中（v0.2.0） |
| `sql/mysql/` | ✅ MySQL 8.0 方言（10 表 + 6 触发器，已在 8.0.12 实测） |

## `ops/` —— 工具

| 文件 | 作用 |
|---|---|
| `install.ps1` | 一键安装：目录 → 配置 → 建表 → 装插件 → 体检（缺依赖会明说） |
| `doctor.ps1` | 体检：配置、库、副本新鲜度、插件、端口（只读） |
| `secret-scan.ps1` | 发布前敏感信息扫描（BLOCK 必须为 0） |

## `docs/` —— 文档

| 文件 | 作用 |
|---|---|
| `00-why.md` | 为什么做这个（含三次失败） |
| `02-memory-design.md` | 注入四段、为什么必须 IDF、三层缺陷复盘 |
| `04-postmortems.md` | 真实事故与修法 |
| `08-permissions-and-antivirus.md` | 权限要求 + 安全软件拦截怎么处理 |
| `11-mysql-acceptance.md` | MySQL 版验收矩阵与限制 |
| `12-mysql-security.md` | MySQL 部署的安全注意事项（账号/端口/备份/字符集） |
| `ROADMAP.md` | 接下来做什么 |
| `09-file-map.md` | 本页 |

## 看代码的建议顺序

```
1) README 的 5 分钟跑起来     —— 先让它动起来
2) docs/02-memory-design.md   —— 理解"为什么这样注入"
3) memory/plugin/index.mjs    —— 看注入到底做了什么
4) docs/04-postmortems.md     —— 我们知道它会怎么坏
```
