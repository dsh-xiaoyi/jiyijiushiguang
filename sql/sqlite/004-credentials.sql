-- SQLite 版 · 凭据库（kind='secret' 的明文口令存这里：这是主人明确授权的例外）
CREATE TABLE IF NOT EXISTS credentials (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT    NOT NULL,
  category   TEXT    NOT NULL,
  address    TEXT,
  username   TEXT,
  secret     TEXT,
  is_active  INTEGER NOT NULL DEFAULT 1,
  created_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  extra      TEXT,
  source_ref TEXT,
  updated_by TEXT,
  UNIQUE (name)
);
CREATE INDEX IF NOT EXISTS IX_credentials_category ON credentials (category, is_active);
