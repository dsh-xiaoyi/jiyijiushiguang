# 贡献指南

## 提交前必须跑

```powershell
powershell -File ops\secret-scan.ps1 -Root .
powershell -File ops\selftest.ps1 -ConfigPath C:\dsh-mem\dsh-mem.config.json
```

- secret-scan 的 BLOCK 必须为 0
- 所有 `.ps1` 必须能过 Parser，且保存为 UTF-8 **带 BOM**
- 新增 SQL 脚本要能重复执行（用 `IF NOT EXISTS` / `OBJECT_ID` 保护）

## 报告问题

带上：`ops\doctor.ps1` 输出（脱敏后）、SQL Server 版本、Windows 版本、完整报错。
**不要贴**：口令、连接串账号、主机名、真实路径里的用户名。

## 风格

- 不做静默失败：出错要打印原因
- 判据一义：一个灯只能有一个解释
- 不替用户关杀软 / 改安全设置
