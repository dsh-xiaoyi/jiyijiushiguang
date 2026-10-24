-- SQLite 版 · 语义检索向量（可选功能；NULL 表示未启用）
CREATE TABLE IF NOT EXISTS embeddings (
  item_type  TEXT    NOT NULL,
  item_id    INTEGER NOT NULL,
  model      TEXT    NOT NULL,
  dim        INTEGER NOT NULL,
  vec        BLOB    NOT NULL,
  text_hash  BLOB    NOT NULL,
  created_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  PRIMARY KEY (item_type, item_id, model)
);
CREATE INDEX IF NOT EXISTS IX_embeddings_model ON embeddings (model, created_at);
