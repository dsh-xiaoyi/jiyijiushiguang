# 记忆旧时光 · dsh-memory-bridge

> 给 DeepSeek Harness（DSH）用的**长期记忆注入插件**：把一份共享的长期记忆库
> 注入到每个会话的系统提示里，让新会话不再是白纸。

版本：**0.5.0** ｜ 许可：MIT ｜ 平台：Windows（PowerShell 5.1+）+ Node.js 18+

---

## 它解决什么问题

DSH 的每个会话都是独立的：昨天定下的规则、上周的结论、上个月的坑，新会话一概不知道。
人工复述既不可靠也不可持续。

这个插件做三件事：

1. **注入**：每 60 秒从一份离线副本（JSON）里读取共享记忆，组装成一段系统提示，包含
   - 关键约定（每次完整注入）
   - 按话题命中的约定分片（最多 3 片）
   - 与当前话题相关的旧记忆（关键词 IDF + 可选的语义检索）
   - 定义型记忆（决策/事实/规则，不按新旧筛）
   - 最近结论（新 → 旧）
   - 各机最近活动
2. **捕获**：会话被压缩时，把摘要落库为 `evidence`（**证据**，不参与注入）。
3. **自证**：每轮在注入末尾追加一行版本尾巴，任何一台机器都能自报"我跑的是哪一版"。

---

## 设计要点（都是踩坑换来的）

| 要点 | 说明 |
|---|---|
| 分段预算 | 每段有独立上限；超限时**列出省略条数**，绝不静默截断 |
| 全局去重 | 同一记忆 id 只出现一次（实测常能省掉 4–8 条重复） |
| 分片按需 | `conventions.d/*.md` 首行写关键词，按命中数排序，最多 3 片 |
| 失败可见 | 副本读不到 / 解析失败 / 配置不合格 ⇒ 在系统提示里用中文写明，而不是清空 |
| 降级注入 | 配置不足时**降级注入 + 明文标注**，而不是直接不注入（"失忆"比"少几条"糟得多） |
| 路径运行时解析 | 配置给的路径不存在就按候选探测，不再需要"每机一套变体" |
| 版本尾巴 | `<!-- conventions@<sha16> size=<B> injector=<ver>-<build> -->`，幂等、可 grep |
| 运行时自报 | `INJECT-EFFCONFIG`（生效配置）、`INJECT-SELFID`（本机身份）、`PATH-RESOLVED`（逐文件路径） |

---

## 安装

```powershell
# 1) 放到任意目录，例如 C:\tools\dsh-memory-bridge
# 2) 在 DSH 的插件配置里按 bundle patch 方式引入（见 examples/config.sample.yml）
# 3) 需要一个可读的离线副本 JSON（replica）与一个记忆 CLI
# 4) 改完插件必须重启一次 DSH（插件在加载期注册）
```

最小配置（`examples/config.sample.yml`）：

```yaml
replicaPath: 'C:\tools\dsh-mem\replica.json'
cliPath:     'C:\tools\dsh-mem\mem.ps1'
conventionsPath: 'C:\tools\dsh-mem\conventions.md'
conventionsDir:  'C:\tools\dsh-mem\conventions.d'
maxChars: 16000
conventionsMax: 8000
refreshMs: 60000
```

---

## 可观测性

注入器每轮向 `logs/inject.log` 写：

```
INJECT-TAIL     版本尾巴（含时间）
INJECT-BUDGET   各段字符数 + 去重数 + 语义状态
INJECT-SHARDS   分片注入/跳过数量
INJECT-EFFCONFIG 生效配置（maxChars / conventionsMax / requiredMin / 来源）
INJECT-SELFID   本机实测身份（主机/OS/登录用户/管理员组）
PATH-RESOLVED   逐文件解析结果（选了哪个、跳过了哪些、大小）
INJECT-FAIL     注入失败（会同时写进系统提示）
```

---

## 配套工具（`ops/`）

| 脚本 | 用途 |
|---|---|
| `release-gate.ps1` | 发布门禁：标记齐全、单产物、文件名含 sha16、语法、尾巴自哈希、不许 UNKNOWN |
| `gen-fix-markers.ps1` | 从产物**机械抽取**修复标记（禁止手抄），带负向对照 |
| `lint-evidence.ps1` | 证据行 lint：必须带「值 + 层级 + 时刻」；回指不算证据 |
| `check-conventions.ps1` | 约定注入自检：超限即报，且证明自己读的是**生效配置** |
| `build-vectors.ps1` | 调 Ollama 批量算向量（用于语义检索） |
| `curate-proposal.ps1` | 只提案的 curator：产出建议报告，**不写库** |

---

## 已知限制

- 语义检索需要本地 Ollama（默认 `bge-m3`，1024 维）；不可用时自动退回关键词检索。
- 向量文件是 **id-keyed** 的，**不能跨机器复制**（副本行集合不同会导致静默错位）。
- 注入内容有上限，超限可见但确实会少几条——**看到"省略 N 条"时请用 CLI 检索补齐**。
- 仅测试了 Windows（PowerShell 5.1 / Node 18+）。

---

## 目录

```
plugin/    注入插件本体（index.mjs + bundle patch + package.json + CHANGELOG）
ops/       配套脚本（门禁 / 标记抽取 / 证据 lint / 向量 / 自检 / curator）
docs/      设计与决策文档（含实测数据）
examples/  配置样例
```

## 与内部部署版的差别（重要）

公开版把两个默认值改成了安全值，行为与内部版一致，但**默认值不同**：

| 项 | 公开版默认 | 内部部署默认 |
|---|---|---|
| `ollamaUrl` | `http://127.0.0.1:11434` | 局域网内的 GPU 节点地址 |

其余代码逐行相同（实测差异仅 4 行，全部是脱敏替换）。
如果你直接复用内部配置，请显式设置 `ollamaUrl`，不要依赖默认值。

## 关于 `verify.mjs`

`verify.mjs` 是 **v0.3.0 时代的参考脚本**（用于核对当时的 replica 格式与 JSON 日期），
当前版本不使用它，也**不参与任何判据**。保留它只为让老版本的排查记录可追溯。

## 许可

MIT，见 LICENSE。
