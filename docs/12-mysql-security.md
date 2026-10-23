# MySQL 部署的安全注意事项

> 记忆库里有**你说过的所有话**（可能还有口令、内网地址、主机名）。用 MySQL 时，这份数据的安全
> 主要由你的数据库负责 —— 这一页是"最少要做到的几件事"，按它做能挡掉绝大多数常见事故。

## 一、账号：绝不要用 root 跑应用

```sql
-- 正确做法：一个库、一个专用账号、只给这个库的权限
CREATE USER 'dsh'@'%' IDENTIFIED WITH mysql_native_password BY '强口令';  -- ≤8.3 用这个
-- 8.4+ 该插件默认禁用：改成 CREATE USER 'dsh'@'%' IDENTIFIED BY '强口令';（用默认 caching_sha2_password）
GRANT ALL PRIVILEGES ON dsh_memory.* TO 'dsh'@'%';
FLUSH PRIVILEGES;
```

```
× 不要用 root 当应用账号（一次泄漏 = 整个实例）
× 不要 GRANT ALL ON *.*
√ 能限定来源就限定：'dsh'@'192.0.2.50' 比 'dsh'@'%' 安全得多
√ 口令别用默认值（我们在测试机上见过 root/root，那只配当测试机）
```

## 二、网络：3306 不要对公网开

```
√ 只监听内网 / 只 127.0.0.1 时，配 bind-address = 127.0.0.1
√ 防火墙只放行"需要连它的那几台机器"
× 不要把 3306 映射到公网（扫描器几分钟内就会找到它）
× 不要在云安全组里写 0.0.0.0/0
```

## 三、触发器权限（`log_bin_trust_function_creators`）

```
建只追加触发器需要 SUPER 或打开：
  SET GLOBAL log_bin_trust_function_creators = 1;
这会略微放宽"谁能创建函数/触发器"的限制（因为开了 binlog）。
√ 建完触发器后可以再关掉：SET GLOBAL log_bin_trust_function_creators = 0;
√ 更好的做法：只在**建表那一次**用高权限账号，日常用 dsh 账号（它不需要这个开关）
× 不要为图省事把它写进全局配置并长期开着
```

## 四、口令不要出现在命令行

```
√ 引擎的做法：把账号/口令写进**临时选项文件**（0600 权限），用 --defaults-extra-file 读取，用完立即删
× mysql -uroot -p密码 …   ← 命令行会被进程列表/历史记录/审计日志看到
× 把口令写进脚本、写进 .sql 文件、写进 git
```

> 补充：临时文件在系统临时目录里，Windows 下该目录的 ACL 默认只对当前用户可读；引擎在 `finally` 里删除。
> 如果你对这一点不放心，可以把 `TEMP` 指到一个你自己加密的目录。

## 五、备份与导出：它们就是明文

```
· mysqldump 出的 .sql、引擎导出的 memories-*.json、副本 JSON —— **全是明文**
· credentials 表本身就是"明文口令库"（这是设计：由你决定存不存）
⇒ 备份要放加密容器（我们自己的做法：7z + 单独保管密钥）
⇒ 副本/导出不要放共享盘、不要进 git（仓库 .gitignore 已经挡了 *-replica.json / *.bak）
```

## 六、字符集：utf8mb4，别用 utf8

```
utf8（3 字节）存不下 emoji 和部分生僻字，会**静默截断**（不报错，很难发现）
√ 建库：CREATE DATABASE dsh_memory CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
√ 建表脚本已经全部显式声明 utf8mb4（sql/mysql/*.sql）
```

## 七、客户端路径（容易被忽略的一处）

```
引擎通过 mysql.exe 执行 SQL，路径来自配置 mysqlCliPath。
√ 写**绝对路径**（例如 D:\phpstudy_pro\...\mysql.exe）
× 只写 "mysql" 依赖 PATH —— 如果 PATH 里被塞了同名程序，就等于让它执行任意代码
```

## 八、同步时的临时 SQL 文件

```
sync 会把整段会话（可能几 MB 文本）写成临时 .sql 再由 mysql.exe 读入。
√ 引擎在 finally 里删除它
√ 若磁盘上有"禁止删除即无法启动"的和审计要求，请自行确认临时目录的 ACL
× 不要把临时目录指到共享盘
```

## 九、最小检查清单（部署完逐项打勾）

```
[ ] 应用账号不是 root，且只授权 dsh_memory.*
[ ] 3306 只在内网可达（或仅 127.0.0.1）
[ ] 口令不在命令行、不在脚本、不在仓库
[ ] 建表用高权限、日常用低权限（两个账号分开）
[ ] 库字符集 utf8mb4
[ ] 备份加密存放，副本/导出不进仓库
[ ] mysqlCliPath 是绝对路径
[ ] 触发器建好后按需关闭 log_bin_trust_function_creators
```
