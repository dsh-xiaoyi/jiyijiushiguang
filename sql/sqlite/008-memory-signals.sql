-- 008-memory-signals.sql · 记忆信号（四阶段 + FTS 检索）
-- SQLite 方言版本（记忆旧时光 · MySQL 版的等价结构）
--
--   [ACCESS-REINFORCE-20261119] 访问加固（access_count / last_injected_at）
--   [VALENCE-CONTEXT-20261119]  情绪价 + 处境上下文（valence / context）
--   [CO-OCCUR-20261119]         共现互链（memory_refs）
--   [MOOD-20261119]             情绪状态变量（agent_state，4 状态 + 漂移）
--   [FTS-SQLITE-20261123]       全文检索（FTS5 虚拟表 + MATCH + 触发器同步）

-- ① memories 加 4 列
--    说明：SQLite 不支持 ALTER TABLE ... ADD COLUMN IF NOT EXISTS，本段为一次性迁移。
--    对「已存在 memories 表」的旧库，重跑本文件时本段会报 duplicate column；
--    新库（install 首次）只执行一次，无此问题。
ALTER TABLE memories ADD COLUMN access_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE memories ADD COLUMN last_injected_at TEXT;
ALTER TABLE memories ADD COLUMN valence INTEGER;
ALTER TABLE memories ADD COLUMN context TEXT;

-- ② 共现互链表
--    UNIQUE(memory_id,cited_id,relation) 供引擎用 INSERT ... ON CONFLICT DO UPDATE 原子累加权重。
CREATE TABLE IF NOT EXISTS memory_refs (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  memory_id  INTEGER NOT NULL,
  cited_id   INTEGER NOT NULL,
  relation   TEXT    NOT NULL,
  weight     INTEGER NOT NULL DEFAULT 0,
  created_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (memory_id, cited_id, relation)
);
CREATE INDEX IF NOT EXISTS IX_memory_refs_cited ON memory_refs (cited_id);

-- ③ 情绪状态变量（4 状态：boredom / curiosity / energy / social_drive）
CREATE TABLE IF NOT EXISTS agent_state (
  state_name TEXT PRIMARY KEY,
  value      REAL NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
INSERT OR IGNORE INTO agent_state (state_name, value) VALUES
  ('boredom', 1.0), ('curiosity', 0.6), ('energy', 0.1), ('social_drive', 0.5);

-- ④ 全文检索（FTS5 外部内容表 + 触发器同步；参照 007 的 DROP TRIGGER IF EXISTS 风格）
CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(text, content='messages', content_rowid='id');
INSERT INTO messages_fts(messages_fts) VALUES('rebuild');

CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(title, body, tags, content='memories', content_rowid='id');
INSERT INTO memories_fts(memories_fts) VALUES('rebuild');

DROP TRIGGER IF EXISTS trg_messages_fts_ai;
CREATE TRIGGER trg_messages_fts_ai AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(rowid, text) VALUES (new.id, new.text);
END;

DROP TRIGGER IF EXISTS trg_messages_fts_ad;
CREATE TRIGGER trg_messages_fts_ad AFTER DELETE ON messages BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, text) VALUES ('delete', old.id, old.text);
END;

DROP TRIGGER IF EXISTS trg_messages_fts_au;
CREATE TRIGGER trg_messages_fts_au AFTER UPDATE ON messages BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, text) VALUES ('delete', old.id, old.text);
  INSERT INTO messages_fts(rowid, text) VALUES (new.id, new.text);
END;

DROP TRIGGER IF EXISTS trg_memories_fts_ai;
CREATE TRIGGER trg_memories_fts_ai AFTER INSERT ON memories BEGIN
  INSERT INTO memories_fts(rowid, title, body, tags) VALUES (new.id, new.title, new.body, new.tags);
END;

DROP TRIGGER IF EXISTS trg_memories_fts_ad;
CREATE TRIGGER trg_memories_fts_ad AFTER DELETE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, title, body, tags) VALUES ('delete', old.id, old.title, old.body, old.tags);
END;

-- 仅在 title/body/tags 变化时才重写 FTS：访问加固（access_count/last_injected_at）不触发，避免每次 search 冗余重建
DROP TRIGGER IF EXISTS trg_memories_fts_au;
CREATE TRIGGER trg_memories_fts_au AFTER UPDATE ON memories
WHEN old.title IS NOT new.title OR old.body IS NOT new.body OR old.tags IS NOT new.tags
BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, title, body, tags) VALUES ('delete', old.id, old.title, old.body, old.tags);
  INSERT INTO memories_fts(rowid, title, body, tags) VALUES (new.id, new.title, new.body, new.tags);
END;
