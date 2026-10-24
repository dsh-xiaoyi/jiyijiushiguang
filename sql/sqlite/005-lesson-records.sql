-- SQLite 版 · 教训记录（守卫/事故复盘）
CREATE TABLE IF NOT EXISTS lesson_records (
  record_id   INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id   INTEGER,
  lesson_no   TEXT,
  title       TEXT    NOT NULL,
  body        TEXT    NOT NULL,
  body_len    INTEGER NOT NULL,
  body_sha16  TEXT    NOT NULL,
  tags        TEXT,
  scope       TEXT,
  subject     TEXT,
  created_at  TEXT,
  moved_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  record_kind TEXT    NOT NULL,
  origin      TEXT,
  happened_at TEXT
);
CREATE INDEX IF NOT EXISTS IX_lesson_kind_moved ON lesson_records (record_kind, moved_at);
CREATE INDEX IF NOT EXISTS IX_lesson_sha16      ON lesson_records (body_sha16);
