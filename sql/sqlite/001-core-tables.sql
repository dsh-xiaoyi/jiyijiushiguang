-- SQLite 版 · 核心表（记忆 / 会话 / 消息 / 归档 / 成员 / 维护开关）
--
-- 与 sql/mysql/001 一一对应，差异只有三处（都是 SQLite 的方言限制）：
--   1) 时间统一存 TEXT：ISO8601 UTC 带毫秒（(strftime('%Y-%m-%dT%H:%M:%fZ','now'))），排序与比较天然正确
--   2) 自增主键用 INTEGER PRIMARY KEY AUTOINCREMENT
--   3) 没有 ON UPDATE CURRENT_TIMESTAMP：updated_at 由应用显式写入（见 docs/14）
--
-- 只追加保护不在本文件：见 007-append-only.sql（SQLite 没有权限，只能用触发器）

PRAGMA journal_mode = WAL;   -- 读写并发更顺；备份请用 .backup 或 VACUUM INTO
PRAGMA foreign_keys = OFF;   -- 与另两个版本一致：不建外键，靠应用保证

-- 维护开关：sync / prune 需要在**同一连接**里临时放行 UPDATE/DELETE
CREATE TABLE IF NOT EXISTS _guard_state (
  key TEXT PRIMARY KEY,
  val INTEGER NOT NULL DEFAULT 0
);
INSERT OR IGNORE INTO _guard_state (key, val) VALUES ('allow_mutation', 0);

CREATE TABLE IF NOT EXISTS memories (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  scope          TEXT    NOT NULL,
  subject        TEXT,
  kind           TEXT    NOT NULL,
  title          TEXT    NOT NULL,
  body           TEXT,
  tags           TEXT,
  source_session TEXT,
  confidence     INTEGER NOT NULL DEFAULT 100,
  created_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX IF NOT EXISTS IX_memories_created ON memories (created_at);
CREATE INDEX IF NOT EXISTS IX_memories_kind    ON memories (kind, created_at);

CREATE TABLE IF NOT EXISTS sessions (
  session_id   TEXT PRIMARY KEY,
  machine      TEXT,
  cwd          TEXT,
  model        TEXT,
  title        TEXT,
  started_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  last_seen_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  event_count  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS IX_sessions_last_seen ON sessions (last_seen_at);

CREATE TABLE IF NOT EXISTS messages (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT    NOT NULL,
  seq        INTEGER NOT NULL,
  turn       INTEGER,
  role       TEXT    NOT NULL,
  text       TEXT,
  created_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (session_id, seq)
);
CREATE INDEX IF NOT EXISTS IX_messages_created ON messages (created_at);
CREATE INDEX IF NOT EXISTS IX_messages_session ON messages (session_id, seq);

CREATE TABLE IF NOT EXISTS messages_history (
  history_id     INTEGER PRIMARY KEY AUTOINCREMENT,
  id             INTEGER NOT NULL,
  session_id     TEXT    NOT NULL,
  seq            INTEGER NOT NULL,
  turn           INTEGER,
  role           TEXT    NOT NULL,
  text           TEXT,
  created_at     TEXT    NOT NULL,
  archived_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  archive_reason TEXT    NOT NULL,
  archived_by    TEXT
);
CREATE INDEX IF NOT EXISTS IX_messages_history_session ON messages_history (session_id, seq);

CREATE TABLE IF NOT EXISTS machines (
  login_name  TEXT PRIMARY KEY,
  machine     TEXT,
  purpose     TEXT,
  first_seen  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  last_seen   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  cli_version TEXT
);
