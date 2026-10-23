-- 005-lesson-records.sql · 教训/复盘归档（只追加）
-- MySQL 8.0 方言版本（记忆旧时光 · SQL Server 版的等价结构）
--
-- 约定：
--   * 字符集统一 utf8mb4；哈希/编号类用 ascii_bin（省空间、按字节比较）
--   * 时间列统一 DATETIME(3)；**连接时执行 SET time_zone='+00:00'**，CURRENT_TIMESTAMP(3) 即为 UTC
--   * 主键用 BIGINT AUTO_INCREMENT（对应 SQL Server 的 IDENTITY）
--   * 可重复执行（IF NOT EXISTS）


CREATE TABLE IF NOT EXISTS `lesson_records` (
  `record_id`   INT          NOT NULL AUTO_INCREMENT,
  `source_id`   INT          NULL,
  `lesson_no`   VARCHAR(32)  NULL,
  `title`       VARCHAR(200) NOT NULL,
  `body`        LONGTEXT     NOT NULL,
  `body_len`    INT          NOT NULL,
  `body_sha16`  CHAR(16)     CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `tags`        VARCHAR(400) NULL,
  `scope`       VARCHAR(64)  NULL,
  `subject`     VARCHAR(64)  NULL,
  `created_at`  DATETIME(3)  NULL,
  `moved_at`    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `record_kind` VARCHAR(24)  NOT NULL,
  `origin`      VARCHAR(120) NULL,
  `happened_at` DATETIME(3)  NULL,
  PRIMARY KEY (`record_id`),
  KEY `IX_lesson_kind_moved` (`record_kind`, `moved_at`),
  KEY `IX_lesson_sha16` (`body_sha16`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
