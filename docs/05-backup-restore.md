# 备份与恢复

## 引擎自带命令

```powershell
# 全库 .bak（SQL Server BACKUP DATABASE）
powershell -File memory\dsh-mem.ps1 backup

# 导出记忆为 JSON（给人读 / 给插件读 / 迁移比对）
powershell -File memory\dsh-mem.ps1 replica
```

备份默认落在 `<配置目录>\backup\`，可用环境变量 `DSH_BACKUP_DIR` 改。

## 恢复（先演练，再上生产）

```powershell
# 1) 只校验，不覆盖任何东西
sqlcmd -E -Q "RESTORE VERIFYONLY FROM DISK='D:\backup\DSHMemory_full.bak' WITH CHECKSUM"

# 2) 恢复到临时库
sqlcmd -E -Q "RESTORE DATABASE DSHMemory_restoretest FROM DISK='D:\backup\DSHMemory_full.bak'
              WITH MOVE 'DSHMemory' TO 'D:\data\restoretest.mdf',
                   MOVE 'DSHMemory_log' TO 'D:\data\restoretest_log.ldf', REPLACE"

# 3) 对平关键表行数（memories / messages / sessions）
# 4) 确认无误后再切换；演练完删掉临时库
sqlcmd -E -Q "DROP DATABASE DSHMemory_restoretest"
```

## 演练判据（缺一条就写"未验证"，别写"应该没问题"）

```
① VERIFYONLY 通过   ② 有耗时/吞吐数字   ③ 关键表行数对平   ④ 临时库删干净
```

## 保留口径（示例）

```
本地 .bak：按需保留最近 N 天（自己建清理任务）
副本 JSON：随时可重建，不必长期留
删除任何备份前：先确认"云端/冷备还有一份"，并且由人决定
```
