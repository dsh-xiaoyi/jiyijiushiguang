-- 004-credentials.sql · 凭据库（可选；只放你自己的口令）
-- MySQL 8.0 方言版本（记忆旧时光 · SQL Server 版的等价结构）
--
-- 约定：
--   * 字符集统一 utf8mb4；哈希/编号类用 ascii_bin（省空间、按字节比较）
--   * 时间列统一 DATETIME(3)；**连接时执行 SET time_zone='+00:00'**，CURRENT_TIMESTAMP(3) 即为 UTC
--   * 主键用 BIGINT AUTO_INCREMENT（对应 SQL Server 的 IDENTITY）
--   * 可重复执行（IF NOT EXISTS）


CREATE TABLE IF NOT EXISTS `credentials` (
  `id`         INT          NOT NULL AUTO_INCREMENT,
  `name`       VARCHAR(160) NOT NULL,
  `category`   VARCHAR(40)  NOT NULL,
  `address`    VARCHAR(300) NULL,
  `username`   VARCHAR(160) NULL,
  `secret`     LONGTEXT     NULL,
  `is_active`  TINYINT(1)   NOT NULL DEFAULT 1,
  `created_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `extra`      LONGTEXT     NULL,
  `source_ref` VARCHAR(160) NULL,
  `updated_by` VARCHAR(120) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UQ_credentials_name` (`name`),
  KEY `IX_credentials_category` (`category`, `is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
