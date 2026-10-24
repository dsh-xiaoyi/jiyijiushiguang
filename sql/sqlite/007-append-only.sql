-- SQLite 版 · 只追加保护（对应 MySQL 的 6 个 BEFORE 触发器）
--
-- 为什么要触发器：SQLite 没有 GRANT/DENY，应用账号和库文件权限是一回事，
-- 所以"消息/归档/教训不许改、不许删"只能靠触发器拦。
--
-- ★ 维护模式：sync（会话导入要 UPDATE/DELETE）与 prune 需要在同一连接里临时放行：
--     UPDATE _guard_state SET val = 1 WHERE key = 'allow_mutation';
--     ... 维护操作 ...
--     UPDATE _guard_state SET val = 0 WHERE key = 'allow_mutation';
--   单文件库没有"会话变量"，所以开关必须落表；用完必须复位（引擎在 finally 里做）。

DROP TRIGGER IF EXISTS trg_messages_no_update;
DROP TRIGGER IF EXISTS trg_messages_no_delete;
DROP TRIGGER IF EXISTS trg_messages_history_no_update;
DROP TRIGGER IF EXISTS trg_messages_history_no_delete;
DROP TRIGGER IF EXISTS trg_lesson_records_no_update;
DROP TRIGGER IF EXISTS trg_lesson_records_no_delete;

CREATE TRIGGER trg_messages_no_update
BEFORE UPDATE ON messages
FOR EACH ROW
WHEN (SELECT COALESCE(val, 0) FROM _guard_state WHERE key = 'allow_mutation') = 0
BEGIN
  SELECT RAISE(ABORT, 'messages is append-only: UPDATE is not allowed');
END;

-- ★ 2026-10-24（v0.3.7）：堵 INSERT OR REPLACE 的后门
--   SQLite 的 REPLACE 冲突算法删旧行时**不触发** BEFORE DELETE 触发器（除非 PRAGMA recursive_triggers=ON），
--   所以 `INSERT OR REPLACE INTO messages(...)` 能在不设 allow_mutation 的情况下静默替换历史行。
--   下面的 BEFORE INSERT 守卫让"同键再插"在任何路径下都被拦住（REPLACE 也要先 INSERT）。
DROP TRIGGER IF EXISTS trg_messages_no_dup_insert;
CREATE TRIGGER trg_messages_no_dup_insert
BEFORE INSERT ON messages
FOR EACH ROW
WHEN (SELECT COALESCE(val, 0) FROM _guard_state WHERE key = 'allow_mutation') = 0
 AND EXISTS (SELECT 1 FROM messages WHERE session_id = NEW.session_id AND seq = NEW.seq)
BEGIN
  SELECT RAISE(ABORT, 'messages is append-only: duplicate (session_id, seq) insert blocked (REPLACE bypass closed)');
END;

CREATE TRIGGER trg_messages_no_delete
BEFORE DELETE ON messages
FOR EACH ROW
WHEN (SELECT COALESCE(val, 0) FROM _guard_state WHERE key = 'allow_mutation') = 0
BEGIN
  SELECT RAISE(ABORT, 'messages is append-only: DELETE is not allowed');
END;

CREATE TRIGGER trg_messages_history_no_update
BEFORE UPDATE ON messages_history
FOR EACH ROW
WHEN (SELECT COALESCE(val, 0) FROM _guard_state WHERE key = 'allow_mutation') = 0
BEGIN
  SELECT RAISE(ABORT, 'messages_history is append-only: UPDATE is not allowed');
END;

CREATE TRIGGER trg_messages_history_no_delete
BEFORE DELETE ON messages_history
FOR EACH ROW
WHEN (SELECT COALESCE(val, 0) FROM _guard_state WHERE key = 'allow_mutation') = 0
BEGIN
  SELECT RAISE(ABORT, 'messages_history is append-only: DELETE is not allowed');
END;

CREATE TRIGGER trg_lesson_records_no_update
BEFORE UPDATE ON lesson_records
FOR EACH ROW
WHEN (SELECT COALESCE(val, 0) FROM _guard_state WHERE key = 'allow_mutation') = 0
BEGIN
  SELECT RAISE(ABORT, 'lesson_records is append-only: UPDATE is not allowed');
END;

CREATE TRIGGER trg_lesson_records_no_delete
BEFORE DELETE ON lesson_records
FOR EACH ROW
WHEN (SELECT COALESCE(val, 0) FROM _guard_state WHERE key = 'allow_mutation') = 0
BEGIN
  SELECT RAISE(ABORT, 'lesson_records is append-only: DELETE is not allowed');
END;
