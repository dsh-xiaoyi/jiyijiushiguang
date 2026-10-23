-- 003-embeddings.sql · 向量（可选，语义检索用）
-- MySQL 8.0 方言版本（记忆旧时光 · SQL Server 版的等价结构）
--
-- 约定：
--   * 字符集统一 utf8mb4；哈希/编号类用 ascii_bin（省空间、按字节比较）
--   * 时间列统一 DATETIME(3)；**连接时执行 SET time_zone='+00:00'**，CURRENT_TIMESTAMP(3) 即为 UTC
--   * 主键用 BIGINT AUTO_INCREMENT（对应 SQL Server 的 IDENTITY）
--   * 可重复执行（IF NOT EXISTS）


CREATE TABLE IF NOT EXISTS `embeddings` (
  `item_type`  VARCHAR(16)  NOT NULL,
  `item_id`    BIGINT       NOT NULL,
  `model`      VARCHAR(64)  NOT NULL,
  `dim`        SMALLINT     NOT NULL,
  `vec`        LONGBLOB     NOT NULL,
  `text_hash`  BINARY(16)   NOT NULL,
  `created_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`item_type`, `item_id`, `model`),
  KEY `IX_embeddings_model` (`model`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
