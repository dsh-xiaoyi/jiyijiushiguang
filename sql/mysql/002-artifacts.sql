-- 002-artifacts.sql · 工件登记
-- MySQL 8.0 方言版本（记忆旧时光 · SQL Server 版的等价结构）
--
-- 约定：
--   * 字符集统一 utf8mb4；哈希/编号类用 ascii_bin（省空间、按字节比较）
--   * 时间列统一 DATETIME(3)；**连接时执行 SET time_zone='+00:00'**，CURRENT_TIMESTAMP(3) 即为 UTC
--   * 主键用 BIGINT AUTO_INCREMENT（对应 SQL Server 的 IDENTITY）
--   * 可重复执行（IF NOT EXISTS）


CREATE TABLE IF NOT EXISTS `artifacts` (
  `id`         BIGINT       NOT NULL AUTO_INCREMENT,
  `machine`    VARCHAR(16)  NULL,
  `path`       VARCHAR(600) NOT NULL,
  `name`       VARCHAR(260) NOT NULL,
  `kind`       VARCHAR(20)  NULL,
  `size_bytes` BIGINT       NULL,
  `sha256`     CHAR(64)     CHARACTER SET ascii COLLATE ascii_bin NULL,
  `mtime`      DATETIME(3)  NULL,
  `first_seen` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `last_seen`  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `status`     VARCHAR(16)  NOT NULL DEFAULT 'active',
  `note`       VARCHAR(400) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UQ_artifacts_path` (`path`),
  KEY `IX_artifacts_status` (`status`, `last_seen`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
