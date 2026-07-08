# GitLab `gitlab-psql` 常用命令速查

本文档面向 GitLab Omnibus（RPM/DEB 安装包，如 `gitlab-ce` / `gitlab-ee` / `gitlab-jh`）部署方式，介绍 `gitlab-psql` 的用途与常用操作，重点覆盖 **只读排障查询**：查看连接、锁、慢查询、库表大小与基础健康信息。

> `gitlab-psql` 是 Omnibus 提供的便捷入口，本质上是带好参数（socket/用户/库名等）的 `psql`。  
> 直接连数据库非常强大也很危险：**不要在生产库随意执行 `UPDATE/DELETE/TRUNCATE/DROP`**。

## 基本用法与注意事项

```bash
# 进入 GitLab 数据库的 psql 交互界面
sudo gitlab-psql
```

- **强烈建议只读**：排障优先用 `SELECT`；不要执行任何写入/DDL
- **先确认服务状态**：数据库异常时，先看 `sudo gitlab-ctl status` 与 `sudo gitlab-ctl tail postgresql`
- **外置 PostgreSQL 场景**：如果你在 `gitlab.rb` 配置了外置数据库，`gitlab-psql` 可能无法直连（或连接到的并非你期望的实例），请以你的外置连接方式为准
- **注意数据敏感性**：SQL 查询结果可能包含邮箱、用户名、Token 等敏感信息

## 与 `psql` / `gitlab-ctl` / `gitlab-rake` 的关系

- **`gitlab-psql`**：快速进入 PostgreSQL（等价于“帮你拼好参数的 `psql`”）
- **`gitlab-ctl`**：查看/管理 PostgreSQL 服务（`status`、`tail postgresql`、`restart postgresql`）
- **`gitlab-rake`**：GitLab 官方任务入口（健康检查、备份/恢复、迁移状态等），一般比手写 SQL 更安全

推荐顺序：

1. 服务状态/日志 → `gitlab-ctl status` / `gitlab-ctl tail postgresql`
2. GitLab 自检 → `gitlab-rake gitlab:check`
3. 仍需深入定位（只读）→ `gitlab-psql` 执行查询

## `psql` 交互常用元命令（不改数据）

进入 `sudo gitlab-psql` 后，你可以用：

```sql
-- 显示帮助
\?

-- 显示当前连接信息
\conninfo

-- 列出数据库
\l

-- 切换数据库（通常不需要）
\c gitlabhq_production

-- 列出 schema / 表 / 视图
\dn
\dt
\dv

-- 查看表结构（含索引等）
\d users
\d+ projects

-- 退出
\q
```

> 提示：`\d`、`\dt` 等是 `psql` 客户端命令，不会直接修改数据。

## 常用只读排障 SQL

### 1）确认数据库版本与基础信息

```sql
select version();
select current_database(), current_user;
show server_version;
```

### 2）查看当前连接数与活动连接

```sql
-- 连接数统计
select
  count(*) as total,
  sum(case when state = 'active' then 1 else 0 end) as active,
  sum(case when state = 'idle' then 1 else 0 end) as idle
from pg_stat_activity
where datname = current_database();

-- 查看当前活动 SQL（可能包含敏感信息，注意脱敏）
select pid, usename, client_addr, state, wait_event_type, wait_event, now() - query_start as running_for, left(query, 200) as query
from pg_stat_activity
where datname = current_database()
order by query_start nulls last;
```

### 3）查看锁与被阻塞情况（定位“卡住/超时/死锁”）

```sql
-- 哪些 pid 正在等待锁
select pid, locktype, mode, granted, relation::regclass as relation, transactionid, virtualtransaction
from pg_locks
where not granted;

-- 找出阻塞链（简化版）
select
  blocked.pid as blocked_pid,
  blocking.pid as blocking_pid,
  left(blocked.query, 120) as blocked_query,
  left(blocking.query, 120) as blocking_query,
  now() - blocked.query_start as blocked_for
from pg_stat_activity blocked
join pg_stat_activity blocking
  on blocking.pid = any (pg_blocking_pids(blocked.pid))
where blocked.datname = current_database();
```

> 说明：如果你看到大量阻塞，优先回到应用层/任务层排查根因（例如升级迁移、批量导入、后台任务堆积），不要在不了解影响时强行 `pg_terminate_backend`。

### 4）查看表/索引大小（定位磁盘增长）

```sql
-- 当前库大小
select pg_size_pretty(pg_database_size(current_database())) as db_size;

-- Top N 大表（含索引与 toast）
select
  relname as table,
  pg_size_pretty(pg_total_relation_size(relid)) as total_size,
  pg_size_pretty(pg_relation_size(relid)) as table_size,
  pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) as index_toast_size
from pg_catalog.pg_statio_user_tables
order by pg_total_relation_size(relid) desc
limit 20;
```

### 5）查看长事务（可能导致 vacuum 受阻/膨胀）

```sql
select pid, usename, state, xact_start, now() - xact_start as xact_age, left(query, 160) as query
from pg_stat_activity
where datname = current_database()
  and xact_start is not null
order by xact_start;
```

## 常见问题

### 1）`gitlab-psql` 找不到

- Omnibus 安装通常自带 `gitlab-psql`。若找不到：
  - 确认 GitLab 是否安装在本机
  - 尝试使用完整路径：

```bash
sudo /opt/gitlab/bin/gitlab-psql
```

### 2）连不上数据库 / 报认证失败

建议顺序：

1. 先看 PostgreSQL 服务是否正常：

```bash
sudo gitlab-ctl status
sudo gitlab-ctl tail postgresql
```

2. 确认是否使用了外置 PostgreSQL（`/etc/gitlab/gitlab.rb` 里的 `postgresql['enable']`、`gitlab_rails['db_*']` 等配置）
3. 若是外置数据库：请用外置连接串/账号登录（此时 `gitlab-psql` 未必适用）

### 3）我应该用 `gitlab-psql` 还是 `gitlab-rake`？

- **能用 `gitlab-rake` 的任务解决就优先用它**（更安全，版本兼容性更好）
- `gitlab-psql` 更适合做底层观察：连接、锁、大小、慢查询与长事务

## 参考链接

- [GitLab Docs - PostgreSQL](https://docs.gitlab.com/administration/postgresql/)
