-- SQLite 版 · 建库自检（应该看到：表 10 张、触发器 6 个、维护开关默认 0）
SELECT 'tables' AS what, COUNT(*) AS n FROM sqlite_master
 WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT IN ('_guard_state');
SELECT 'views' AS what, COUNT(*) AS n FROM sqlite_master WHERE type = 'view' AND name NOT LIKE 'sqlite_%';
SELECT 'triggers' AS what, COUNT(*) AS n FROM sqlite_master WHERE type = 'trigger';
SELECT 'indexes' AS what, COUNT(*) AS n FROM sqlite_master WHERE type = 'index' AND name LIKE 'IX_%';
SELECT 'allow_mutation_default' AS what, val AS n FROM _guard_state WHERE key = 'allow_mutation';
SELECT 'journal_mode' AS what, (SELECT * FROM pragma_journal_mode) AS n;
