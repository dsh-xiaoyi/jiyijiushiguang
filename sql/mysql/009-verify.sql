-- 009-verify.sql · 建完自检
-- MySQL 8.0 方言版本（记忆旧时光 · SQL Server 版的等价结构）
--
-- 约定：
--   * 字符集统一 utf8mb4；哈希/编号类用 ascii_bin（省空间、按字节比较）
--   * 时间列统一 DATETIME(3)；**连接时执行 SET time_zone='+00:00'**，CURRENT_TIMESTAMP(3) 即为 UTC
--   * 主键用 BIGINT AUTO_INCREMENT（对应 SQL Server 的 IDENTITY）
--   * 可重复执行（IF NOT EXISTS）


SELECT 'tables' AS check_item, COUNT(*) AS n
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('memories','sessions','messages','messages_history','machines',
                     'artifacts','embeddings','credentials','lesson_records','llm_retries');

SELECT 'triggers' AS check_item, COUNT(*) AS n
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = DATABASE();

SELECT TABLE_NAME, ENGINE, TABLE_COLLATION
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
ORDER BY TABLE_NAME;
