-- SQLite 版 · 模型重试事件（对账用）
CREATE TABLE IF NOT EXISTS llm_retries (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  machine     TEXT    NOT NULL,
  session_id  TEXT,
  retry_id    TEXT    NOT NULL,
  at_utc      TEXT    NOT NULL,
  turn        INTEGER,
  step        INTEGER,
  attempt     INTEGER NOT NULL,
  max_retries INTEGER,
  delay_ms    REAL,
  code        TEXT,
  message     TEXT,
  imported_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (machine, retry_id)
);
CREATE INDEX IF NOT EXISTS IX_llm_retries_at ON llm_retries (at_utc);
