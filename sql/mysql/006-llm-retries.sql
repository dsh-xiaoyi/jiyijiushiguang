-- 006-llm-retries.sql · 模型重试记录（可选，观测用）
-- MySQL 8.0 方言版本（记忆旧时光 · SQL Server 版的等价结构）
--
-- 约定：
--   * 字符集统一 utf8mb4；哈希/编号类用 ascii_bin（省空间、按字节比较）
--   * 时间列统一 DATETIME(3)；**连接时执行 SET time_zone='+00:00'**，CURRENT_TIMESTAMP(3) 即为 UTC
--   * 主键用 BIGINT AUTO_INCREMENT（对应 SQL Server 的 IDENTITY）
--   * 可重复执行（IF NOT EXISTS）


CREATE TABLE IF NOT EXISTS `llm_retries` (
  `id`          BIGINT       NOT NULL AUTO_INCREMENT,
  `machine`     VARCHAR(60)  NOT NULL,
  `session_id`  VARCHAR(160) NULL,
  `retry_id`    VARCHAR(64)  NOT NULL,
  `at_utc`      DATETIME(3)  NOT NULL,
  `turn`        INT          NULL,
  `step`        INT          NULL,
  `attempt`     INT          NOT NULL,
  `max_retries` INT          NULL,
  `delay_ms`    DOUBLE       NULL,
  `code`        VARCHAR(40)  NULL,
  `message`     VARCHAR(240) NULL,
  `imported_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `UQ_llm_retries` (`machine`, `retry_id`),
  KEY `IX_llm_retries_at` (`at_utc`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
