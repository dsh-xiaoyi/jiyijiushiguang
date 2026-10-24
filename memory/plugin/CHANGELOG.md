# CHANGELOG — dsh-memory-bridge

> 状态：**未发布**（2026-10-24 起内部验收中；验收通过后再决定是否开源/发版）
> 命名：v0.5.0 对应"记忆插件 v2"改造（A/B/C 三阶段）

## [0.5.0] — 2026-10-24（内部，未发布）

### 注入契约（A + B1/B2）

- **分段预算**：`SECTIONS` + `SEC_BUDGET`
  `conv 8000` ｜ `shards 2600` ｜ `recall 1600` ｜ `pinned 1200` ｜ `recent 2000` ｜ `activity 700` ｜ `hints 400`
  超预算不再静默 `slice`，改为追加「…（本段超出预算，省略 N 条；用 search/recent 取更多）」。
- **总量可见**：超过 `maxChars`（16000）时写 `INJECT-TOTAL-TRUNC` 并在尾部标注。
- **全局去重**：同一 `id` 只出现一次（recall > conv > shards > pinned > recent > activity > hints），
  计数写进 `INJECT-BUDGET` 的 `dup`。
- **上限来源对齐**：生效值来自 bundle patch（`cordis.patch.yml`），自检脚本读生效配置而非代码默认。
- **配置默认值**：`maxChars 16000`、`conventionsMax 8000`。

### 分片约定（B5）

- `conventions.d/*.md`：首行写 `[关键词 …]`；按命中关键词数量排序，**最多注入 3 片**（`config.shardCap`）。
- 未命中或超出上限的分片合并成一行清单（相当于目录），不占预算。

### 话题源（B3）

- 只取最近 3 条「真实用户发言」：长度 <10 忽略、纯寒暄（好的/收到/继续/ok…）忽略。

### 混合检索（C4）

- 新增可选语义检索：本地 `bge-m3`（1024 维）向量 + 现有 IDF 关键词。
- 向量缓存：`C:\dsh-mem\mem-vectors.bin`（二进制：magic/`DSHVEC01`、dim、count、时间戳、`id + float32[]`），
  由 `ops\build-vectors.ps1` 通过 18 上的 Ollama（`/api/embed`）批量生成。
- 打分：`final = 0.55 * min(1, lex/3) + 0.45 * cosine`；语义可单独入选（`semMinFinal 0.32`）。
- 降级：向量文件缺失 / Ollama 不可达 / 维度不符 → 自动退回纯 IDF，并在 `INJECT-BUDGET.semantic` 标注原因。
- 注入行：保留 `‹命中: …›`，语义命中另标 `‹语义 0.72›`。

### 数据模型（C1/C2，SQL Server）

- `dbo.memories` 新增列：`valid_from`、`valid_to`、`status`（默认 `current`）、`revision`、
  `replaced_by`、`importance`（默认 50）、`access_count`、`last_injected_at` + 索引 `IX_memories_status`。
- 新表 `dbo.memory_events`（append-only 审计：`add/merge/supersede/retire/reject/inject`，含 before/after hash）。
- 新表 `dbo.memory_links`（`supersedes/duplicates/refines/derived_from/evidence_of`）。
- 引擎 `save` 成功后自动写一条 `action='add'`（body 的 SHA256）。
- **"删除"= `status='retired'`**，行永不物理删除。

### 捕获语义（C3）

- 会话压缩摘要改为 `kind='evidence'`（不再叫 `checkpoint`），**不参与注入**。
- 注入端排除：`kind ∈ {checkpoint, evidence, llm-call}`、`status ∈ {retired, archived}`。
- 非 `current` 状态在行尾标注：`‹状态: superseded，已被 [id] 取代›`。

### 检索修复（B4，引擎侧）

- `LIKE` 通配符转义（`[[]` `[%]` `[_]`）；多词按 **AND** 拆开。
- 排序：`checkpoint` 垫底 → 标题命中优先 → `updated_at DESC`。
- 反例前后：`备份_` 440→2 ｜ `"共享盘 SMB"` 0→6 ｜ `备份` 前 6 条 checkpoint 8→0。

### 可观测性（A4）

- `C:\dsh-mem\logs\inject.log`：每轮 `INJECT-BUDGET`、`INJECT-SHARDS`、`INJECT-TRUNC`、
  `INJECT-TOTAL-TRUNC`、`INJECT-FAIL`、`SEMANTIC-OK`。
- `ops\check-conventions.ps1` + 每日任务 `DSH_ConventionsCheck`（06:50）：超限当场报警。

### 故障可见（A2）

- 副本原子写（`.tmp` + `Move-Item -Force`）。
- 插件读取/解析失败不再清空 digest，改为在系统提示里写**汉字告警**（原因 + 副本路径 + 处理建议）。

### 维护脚本安全（A3）

- `mem-maintenance.ps1` 新增 `-AllowDelete`；没有它时 `-Apply` 自动降级为 DRY-RUN（只报告，不删）。
