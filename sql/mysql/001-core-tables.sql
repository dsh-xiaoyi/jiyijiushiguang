-- 001-core-tables.sql · 记忆核心表
-- MySQL 8.0 方言版本（记忆旧时光 · SQL Server 版的等价结构）
--
-- 约定：
--   * 字符集统一 utf8mb4；哈希/编号类用 ascii_bin（省空间、按字节比较）
--   * 时间列统一 DATETIME(3)；**连接时执行 SET time_zone='+00:00'**，CURRENT_TIMESTAMP(3) 即为 UTC
--   * 主键用 BIGINT AUTO_INCREMENT（对应 SQL Server 的 IDENTITY）
--   * 可重复执行（IF NOT EXISTS）


-- 记忆条目
CREATE TABLE IF NOT EXISTS `memories` (
  `id`             BIGINT       NOT NULL AUTO_INCREMENT,
  `scope`          VARCHAR(32)  NOT NULL,
  `subject`        VARCHAR(64)  NULL,
  `kind`           VARCHAR(32)  NOT NULL,
  `title`          VARCHAR(200) NOT NULL,
  `body`           LONGTEXT     NULL,
  `tags`           VARCHAR(200) NULL,
  `source_session` VARCHAR(64)  NULL,
  `confidence`     TINYINT      NOT NULL DEFAULT 100,
  `created_at`     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `IX_memories_scope` (`scope`, `subject`, `kind`),
  KEY `IX_memories_kind_created` (`kind`, `created_at`),
  KEY `IX_memories_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- 会话
CREATE TABLE IF NOT EXISTS `sessions` (
  `session_id`   VARCHAR(64)  NOT NULL,
  `machine`      VARCHAR(64)  NULL,
  `cwd`          VARCHAR(400) NULL,
  `model`        VARCHAR(64)  NULL,
  `title`        VARCHAR(200) NULL,
  `started_at`   DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `last_seen_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `event_count`  INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (`session_id`),
  KEY `IX_sessions_machine_seen` (`machine`, `last_seen_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- 消息（只追加）
CREATE TABLE IF NOT EXISTS `messages` (
  `id`         BIGINT       NOT NULL AUTO_INCREMENT,
  `session_id` VARCHAR(64)  NOT NULL,
  `seq`        BIGINT       NOT NULL,
  `turn`       INT          NULL,
  `role`       VARCHAR(24)  NOT NULL,
  `text`       LONGTEXT     NULL,
  `created_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `UQ_messages_sess` (`session_id`, `seq`),
  KEY `IX_messages_time` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- 归档历史（只追加）
CREATE TABLE IF NOT EXISTS `messages_history` (
  `history_id`     BIGINT       NOT NULL AUTO_INCREMENT,
  `id`             BIGINT       NOT NULL,
  `session_id`     VARCHAR(64)  NOT NULL,
  `seq`            BIGINT       NOT NULL,
  `turn`           INT          NULL,
  `role`           VARCHAR(24)  NOT NULL,
  `text`           LONGTEXT     NULL,
  `created_at`     DATETIME(3)  NOT NULL,
  `archived_at`    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `archive_reason` VARCHAR(16)  NOT NULL,
  `archived_by`    VARCHAR(128) NULL,
  PRIMARY KEY (`history_id`),
  KEY `IX_messages_history_sess` (`session_id`, `seq`),
  KEY `IX_messages_history_at` (`archived_at`),
  KEY `IX_messages_history_orig` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- 机器名录
CREATE TABLE IF NOT EXISTS `machines` (
  `login_name`  VARCHAR(128) NOT NULL,
  `machine`     VARCHAR(128) NULL,
  `purpose`     VARCHAR(200) NULL,
  `first_seen`  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `last_seen`   DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `cli_version` VARCHAR(24)  NULL,
  PRIMARY KEY (`login_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
