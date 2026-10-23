-- 007-append-only.sql · 只追加保护（替代 SQL Server 的 DENY UPDATE/DELETE）
-- MySQL 8.0 方言版本（记忆旧时光 · SQL Server 版的等价结构）
--
-- 约定：
--   * 字符集统一 utf8mb4；哈希/编号类用 ascii_bin（省空间、按字节比较）
--   * 时间列统一 DATETIME(3)；**连接时执行 SET time_zone='+00:00'**，CURRENT_TIMESTAMP(3) 即为 UTC
--   * 主键用 BIGINT AUTO_INCREMENT（对应 SQL Server 的 IDENTITY）
--   * 可重复执行（IF NOT EXISTS）

--
-- MySQL 没有 DENY 权限，用触发器拦截 UPDATE/DELETE。
--
-- ★ 权限要求（实测踩过）：
--   开启 binlog 时，建触发器需要 SUPER 或全局打开 log_bin_trust_function_creators：
--     SET GLOBAL log_bin_trust_function_creators = 1;   -- 需要 root；写进 my.ini 才能重启后保留
--   否则会报：ERROR 1419 ... You do not have the SUPER privilege and binary logging is enabled

-- 允许事后维护的场景（如归档）请显式 DROP TRIGGER，做完再建回来 —— 不要偷偷放宽。

DROP TRIGGER IF EXISTS `trg_messages_no_update`;
DROP TRIGGER IF EXISTS `trg_messages_no_delete`;
DROP TRIGGER IF EXISTS `trg_messages_history_no_update`;
DROP TRIGGER IF EXISTS `trg_messages_history_no_delete`;
DROP TRIGGER IF EXISTS `trg_lesson_records_no_update`;
DROP TRIGGER IF EXISTS `trg_lesson_records_no_delete`;

DELIMITER $$

CREATE TRIGGER `trg_messages_no_update` BEFORE UPDATE ON `messages` FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'messages is append-only: UPDATE is not allowed';
END$$

CREATE TRIGGER `trg_messages_no_delete` BEFORE DELETE ON `messages` FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'messages is append-only: DELETE is not allowed';
END$$

CREATE TRIGGER `trg_messages_history_no_update` BEFORE UPDATE ON `messages_history` FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'messages_history is append-only: UPDATE is not allowed';
END$$

CREATE TRIGGER `trg_messages_history_no_delete` BEFORE DELETE ON `messages_history` FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'messages_history is append-only: DELETE is not allowed';
END$$

CREATE TRIGGER `trg_lesson_records_no_update` BEFORE UPDATE ON `lesson_records` FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'lesson_records is append-only: UPDATE is not allowed';
END$$

CREATE TRIGGER `trg_lesson_records_no_delete` BEFORE DELETE ON `lesson_records` FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'lesson_records is append-only: DELETE is not allowed';
END$$

DELIMITER ;
