-- SQLite 版 · 工件登记表
CREATE TABLE IF NOT EXISTS artifacts (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  machine    TEXT,
  path       TEXT NOT NULL,
  name       TEXT NOT NULL,
  kind       TEXT,
  size_bytes INTEGER,
  sha256     TEXT,
  mtime      TEXT,
  first_seen TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  last_seen  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  status     TEXT NOT NULL DEFAULT 'active',
  note       TEXT,
  UNIQUE (path)
);
CREATE INDEX IF NOT EXISTS IX_artifacts_status ON artifacts (status, last_seen);
