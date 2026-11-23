-- 011-memory-signals.sql · 记忆信号（四阶段 + FTS 检索）
-- 记忆旧时光 · SQL Server 方言。全部幂等（可重复执行）。
--
-- 覆盖特性：
--   [ACCESS-REINFORCE-20261119] 访问加固（access_count / last_injected_at）
--   [VALENCE-CONTEXT-20261119]  情绪价 + 处境上下文（valence / context）
--   [CO-OCCUR-20261119]         共现互链（memory_refs）
--   [MOOD-20261119]             情绪状态变量（agent_state，4 状态 + 漂移）
--   [FTS-SQLSERVER-20261123]    全文检索（FREETEXTTABLE，LANGUAGE 2052）

-- ① memories 加 4 列（本仓 SQL Server 方言的核心表由既有库提供；表不存在则整体跳过）
IF OBJECT_ID('dbo.memories') IS NOT NULL
BEGIN
  IF COL_LENGTH('dbo.memories','access_count') IS NULL
    ALTER TABLE dbo.memories ADD access_count int NOT NULL CONSTRAINT DF_memories_access_count DEFAULT (0);
  IF COL_LENGTH('dbo.memories','last_injected_at') IS NULL
    ALTER TABLE dbo.memories ADD last_injected_at datetime2(3) NULL;
  IF COL_LENGTH('dbo.memories','valence') IS NULL
    ALTER TABLE dbo.memories ADD valence tinyint NULL;
  IF COL_LENGTH('dbo.memories','context') IS NULL
    ALTER TABLE dbo.memories ADD context nvarchar(max) NULL;
END
GO

-- ② 共现互链表（同一次查询同时命中的记忆，两两记一条共现边，weight 累加）
IF OBJECT_ID('dbo.memory_refs') IS NULL
BEGIN
  CREATE TABLE dbo.memory_refs (
    id         bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_memory_refs PRIMARY KEY,
    memory_id  bigint       NOT NULL,
    cited_id   bigint       NOT NULL,
    relation   varchar(24)  NOT NULL,
    weight     int          NOT NULL CONSTRAINT DF_memory_refs_weight DEFAULT (0),
    created_at datetime2(3) NOT NULL CONSTRAINT DF_memory_refs_created DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_memory_refs_memory ON dbo.memory_refs (memory_id);
  CREATE INDEX IX_memory_refs_cited  ON dbo.memory_refs (cited_id);
END
GO

-- ③ 情绪状态变量（4 状态：boredom / curiosity / energy / social_drive）
IF OBJECT_ID('dbo.agent_state') IS NULL
BEGIN
  CREATE TABLE dbo.agent_state (
    state_name varchar(32) NOT NULL CONSTRAINT PK_agent_state PRIMARY KEY,
    value      float       NOT NULL CONSTRAINT DF_agent_state_value DEFAULT (0),
    updated_at datetime2(3) NOT NULL CONSTRAINT DF_agent_state_updated DEFAULT SYSUTCDATETIME()
  );
  INSERT INTO dbo.agent_state (state_name, value) VALUES
    ('boredom', 1.0), ('curiosity', 0.6), ('energy', 0.1), ('social_drive', 0.5);
END
GO

-- ④ 全文检索（幂等：sys.fulltext_indexes 已存在则跳过）
--    KEY INDEX 必须引用一个唯一索引；本仓核心表的 PK 名是 SQL Server 自动生成的
--    PK__... 形式，无法硬编码，故用动态 SQL 从 sys.indexes 取真实 PK 名。
IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = 'ft_dsh_memory')
  CREATE FULLTEXT CATALOG ft_dsh_memory AS DEFAULT;
GO

IF OBJECT_ID('dbo.memories') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID('dbo.memories'))
BEGIN
  DECLARE @mem_pk sysname;
  SELECT @mem_pk = i.name FROM sys.indexes i WHERE i.object_id = OBJECT_ID('dbo.memories') AND i.is_primary_key = 1;
  IF @mem_pk IS NOT NULL
    EXEC ('CREATE FULLTEXT INDEX ON dbo.memories (title LANGUAGE 2052, body LANGUAGE 2052, tags LANGUAGE 2052) KEY INDEX ' + QUOTENAME(@mem_pk) + ' WITH CHANGE_TRACKING AUTO');
END
GO

IF OBJECT_ID('dbo.messages') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID('dbo.messages'))
BEGIN
  DECLARE @msg_pk sysname;
  SELECT @msg_pk = i.name FROM sys.indexes i WHERE i.object_id = OBJECT_ID('dbo.messages') AND i.is_primary_key = 1;
  IF @msg_pk IS NOT NULL
    EXEC ('CREATE FULLTEXT INDEX ON dbo.messages (text LANGUAGE 2052) KEY INDEX ' + QUOTENAME(@msg_pk) + ' WITH CHANGE_TRACKING AUTO');
END
GO
