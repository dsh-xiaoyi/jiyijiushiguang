-- 012-text-hash1200.sql
-- [OPENSOURCE-20261124][TEXT-HASH1200-20261124] 方案A：dbo.messages 增加持久化列 text_hash1200 + 非聚簇索引。
--
-- 为什么（实测）：Get-MessagesByHash 原来用 HASHBYTES('MD5', LEFT(text,1200)) IN (N 字面量)，
--   无法走索引，对 600MB / 12 万行的 dbo.messages 做了约 20 遍全表扫（占 recall 42s 的 75%）。
--   改为持久化列 + 非聚簇索引后毫秒级。列由写入路径维护（dsh-mem.ps1 的 INSERT/UPDATE）。
--
-- 三方言说明：本增量仅 SQL Server。
--   · MySQL/SQLite 的 messages 表无 text_hash1200 列（该仓未建等价列）。
--   · 代码里做降级判断：Get-MessagesByHash 在非 sqlserver 方言直接返回空 → 调用方回退 Get-MessagesById。
--   · 写入路径（dsh-mem.ps1）只在 SQL Server 分支维护 text_hash1200；MySQL/SQLite 用各自内联 MD5 做变更检测、不落列。
--
-- 只出增量迁移脚本，不在此执行 DDL。执行（Windows 集成身份 / sysadmin）：
--   sqlcmd -S 192.0.2.11,1433 -d DSHMemory -E -i 012-text-hash1200.sql

IF COL_LENGTH('dbo.messages', 'text_hash1200') IS NULL
BEGIN
  ALTER TABLE dbo.messages ADD text_hash1200 binary(16) NULL;
  -- 一次性回填历史行（大表可分批执行；回填后该列不再 NULL）
  UPDATE dbo.messages SET text_hash1200 = CONVERT(binary(16), HASHBYTES('MD5', LEFT(ISNULL(text,''),1200))) WHERE text_hash1200 IS NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_messages_text_hash1200' AND object_id = OBJECT_ID('dbo.messages'))
BEGIN
  CREATE NONCLUSTERED INDEX IX_messages_text_hash1200 ON dbo.messages (text_hash1200);
END
GO
