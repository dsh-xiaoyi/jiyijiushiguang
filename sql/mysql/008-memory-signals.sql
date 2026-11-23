-- 008-memory-signals.sql · 记忆信号（四阶段 + FTS 检索）
-- MySQL 8.0 方言版本（记忆旧时光 · SQL Server 版的等价结构）
-- 约定同 001：utf8mb4 / DATETIME(3) / BIGINT AUTO_INCREMENT / 可重复执行（幂等）。
--
--   [ACCESS-REINFORCE-20261119] 访问加固（access_count / last_injected_at）
--   [VALENCE-CONTEXT-20261119]  情绪价 + 处境上下文（valence / context）
--   [CO-OCCUR-20261119]         共现互链（memory_refs）
--   [MOOD-20261119]             情绪状态变量（agent_state，4 状态 + 漂移）
--   [FTS-MYSQL-20261123]        全文检索（MATCH ... AGAINST，FULLTEXT INDEX）

-- ① memories 加 4 列（MySQL 无 ADD COLUMN IF NOT EXISTS，用 information_schema + PREPARE 幂等）
SET @c = (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='memories' AND COLUMN_NAME='access_count');
SET @s = IF(@c=0, 'ALTER TABLE memories ADD COLUMN access_count INT NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c = (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='memories' AND COLUMN_NAME='last_injected_at');
SET @s = IF(@c=0, 'ALTER TABLE memories ADD COLUMN last_injected_at DATETIME(3) NULL', 'SELECT 1');
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c = (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='memories' AND COLUMN_NAME='valence');
SET @s = IF(@c=0, 'ALTER TABLE memories ADD COLUMN valence TINYINT NULL', 'SELECT 1');
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c = (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='memories' AND COLUMN_NAME='context');
SET @s = IF(@c=0, 'ALTER TABLE memories ADD COLUMN context TEXT NULL', 'SELECT 1');
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ② 共现互链表
--    UNIQUE(memory_id,cited_id,relation) 供引擎用 INSERT ... ON DUPLICATE KEY UPDATE 原子累加权重。
CREATE TABLE IF NOT EXISTS `memory_refs` (
  `id`         BIGINT       NOT NULL AUTO_INCREMENT,
  `memory_id`  BIGINT       NOT NULL,
  `cited_id`   BIGINT       NOT NULL,
  `relation`   VARCHAR(24)  NOT NULL,
  `weight`     INT          NOT NULL DEFAULT 0,
  `created_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_memory_refs_edge` (`memory_id`, `cited_id`, `relation`),
  KEY `IX_memory_refs_cited` (`cited_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ③ 情绪状态变量（4 状态：boredom / curiosity / energy / social_drive）
CREATE TABLE IF NOT EXISTS `agent_state` (
  `state_name` VARCHAR(32) NOT NULL,
  `value`      DOUBLE      NOT NULL DEFAULT 0,
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`state_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT IGNORE INTO `agent_state` (`state_name`, `value`) VALUES
  ('boredom', 1.0), ('curiosity', 0.6), ('energy', 0.1), ('social_drive', 0.5);

-- ④ 全文检索（FULLTEXT INDEX；幂等：information_schema.STATISTICS 已存在则跳过）
SET @c = (SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='messages' AND INDEX_NAME='ft_messages_text');
SET @s = IF(@c=0, 'ALTER TABLE messages ADD FULLTEXT INDEX ft_messages_text (text)', 'SELECT 1');
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c = (SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='memories' AND INDEX_NAME='ft_memories_title_body_tags');
SET @s = IF(@c=0, 'ALTER TABLE memories ADD FULLTEXT INDEX ft_memories_title_body_tags (title, body, tags)', 'SELECT 1');
PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;
