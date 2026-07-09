# GitLab `gitlab-redis-cli` 常用命令速查

本文档面向 GitLab Omnibus（RPM/DEB 安装包，如 `gitlab-ce` / `gitlab-ee` / `gitlab-jh`）部署方式，介绍 `gitlab-redis-cli` 的用途与常用操作，重点覆盖 **只读排障**：查看连通性、内存、命中率、客户端连接与 Sidekiq 相关队列概况。

> `gitlab-redis-cli` 是 Omnibus 提供的便捷入口，本质上是带好参数（socket/密码等）的 `redis-cli`。  
> Redis 中保存了缓存、Session，以及 Sidekiq 队列等关键数据。**不要在生产环境随意执行 `FLUSHALL` / `FLUSHDB` / `DEL` / `KEYS *` 等破坏性或高成本命令。**

## 基本用法与注意事项

```bash
# 进入 GitLab Redis 的 redis-cli 交互界面
sudo gitlab-redis-cli
```

也可以直接执行单条命令（非交互）：

```bash
sudo gitlab-redis-cli PING
sudo gitlab-redis-cli INFO
sudo gitlab-redis-cli INFO memory
```

- **强烈建议只读**：排障优先用 `PING`、`INFO`、`CLIENT LIST`、`LLEN`、`SCARD` 等
- **先确认服务状态**：Redis 异常时，先看 `sudo gitlab-ctl status` 与 `sudo gitlab-ctl tail redis`
- **外置 Redis 场景**：如果你在 `gitlab.rb` 配置了外置 Redis，`gitlab-redis-cli` 可能连不上、或连到的不是目标实例，请改用外置 Redis 的连接方式
- **注意数据敏感性**：`CLIENT LIST`、部分 key 内容可能含 IP、会话等信息，输出时注意脱敏
- **避免 `KEYS *`**：大数据量实例上可能阻塞 Redis；需要扫描时用 `SCAN`

## 与 `redis-cli` / `gitlab-ctl` / `gitlab-rake` 的关系

- **`gitlab-redis-cli`**：快速进入 GitLab 使用的 Redis（等价于“帮你拼好参数的 `redis-cli`”）
- **`gitlab-ctl`**：查看/管理 Redis 服务（`status`、`tail redis`、`restart redis`）
- **`gitlab-rake`**：更安全的应用层清理入口，例如 `cache:clear`（比手写 `FLUSHDB` 更可控）

推荐顺序：

1. 服务状态/日志 → `gitlab-ctl status` / `gitlab-ctl tail redis`
2. 应用侧异常（页面卡住、异步不跑）→ 看 `sidekiq` 日志与状态
3. 仍需深入定位（只读）→ `gitlab-redis-cli` 执行查询

## Redis 在 GitLab 中的常见作用

| 用途 | 说明 |
|------|------|
| 缓存 | Rails/应用缓存数据 |
| Session | 用户登录会话 |
| Sidekiq 队列 | 邮件、Pipeline、仓库相关异步任务等 |
| 分布式锁 / 限流等 | 部分组件依赖 Redis 协调 |

因此典型现象可能与 Redis 相关：

- 频繁掉登录态 / Session 异常
- 页面“一直转圈”、MR/Issue 状态不更新（Sidekiq 队列堆积或 Redis 不可用）
- 缓存异常导致页面/配置显示不符合预期

## 常用只读排障命令

### 1）连通性与基础信息

```bash
sudo gitlab-redis-cli PING
# 期望返回：PONG

sudo gitlab-redis-cli INFO server
sudo gitlab-redis-cli INFO clients
sudo gitlab-redis-cli INFO memory
sudo gitlab-redis-cli INFO stats
sudo gitlab-redis-cli INFO keyspace
```

交互模式下也可以：

```text
PING
INFO
INFO memory
DBSIZE
```

### 2）查看内存与客户端连接

```bash
# 已用内存概览
sudo gitlab-redis-cli INFO memory | egrep 'used_memory_human|maxmemory_human|mem_fragmentation_ratio'

# 客户端连接数
sudo gitlab-redis-cli INFO clients | egrep 'connected_clients|blocked_clients'

# 客户端列表（输出较长，注意脱敏）
sudo gitlab-redis-cli CLIENT LIST
```

### 3）查看缓存命中粗略指标

```bash
sudo gitlab-redis-cli INFO stats | egrep 'keyspace_hits|keyspace_misses|evicted_keys|expired_keys'
```

> `evicted_keys` 持续增长且内存紧张时，可能需要检查 `maxmemory` 策略与实例规格。

### 4）Sidekiq 队列概况（只读）

Sidekiq 使用 Redis 存储队列。不同 GitLab 版本 key 命名可能略有差异，以下为常见观察方式：

```bash
# 查看 Sidekiq 相关 key（谨慎：大数据量时不要用 KEYS *）
sudo gitlab-redis-cli --scan --pattern '*sidekiq*'

# 查看哪些 key 是 list 类型
sudo gitlab-redis-cli --scan | while read key; do
    if [ "$(sudo gitlab-redis-cli type "$key")" = "list" ]; then
        echo "$key"
    fi
done


# 查看某个 list 队列长度（把 queue 名换成实际队列）
sudo gitlab-redis-cli LLEN queue:default
sudo gitlab-redis-cli LLEN queue:mailers

# 查看 set/zset 类 key 的元素数量（示例）
sudo gitlab-redis-cli SCARD <key>
sudo gitlab-redis-cli ZCARD <key>
```

> 更推荐先用应用层视角排查：`sudo gitlab-ctl status`、`sudo gitlab-ctl tail sidekiq`，以及 Admin UI 中的 Sidekiq 面板（若可用）。`gitlab-redis-cli` 适合确认 Redis 层面是否“连得上、有堆积迹象”。

### 5）安全扫描某个 pattern 的 key（避免 `KEYS *`）

```bash
sudo gitlab-redis-cli --scan --pattern 'cache:*' | head
```

## 清理与高风险操作（慎用）

一般情况下：

- **清理应用缓存**：优先用

```bash
sudo gitlab-rake cache:clear
```

- **不要**轻易执行：

```bash
# 高风险：清空当前 DB（严禁随手执行）
FLUSHDB

# 高风险：清空全部 DB
FLUSHALL
```

若必须手动删某个明确无用的 key，也应先确认它是什么、是否被 Sidekiq/Session 使用，并在低峰操作：

```bash
# 示例：仅作语法说明，生产勿直接照搬
# sudo gitlab-redis-cli DEL some:exact:key
```

## 常见问题

### 1）`gitlab-redis-cli` 找不到

- Omnibus 安装通常自带 `gitlab-redis-cli`。若找不到：
  - 确认 GitLab 是否安装在本机
  - 尝试使用完整路径：

```bash
sudo /opt/gitlab/bin/gitlab-redis-cli PING
```

### 2）连不上 Redis / 报 NOAUTH / Connection refused

建议顺序：

1. 先看 Redis 服务是否正常：

```bash
sudo gitlab-ctl status
sudo gitlab-ctl tail redis
```

2. 确认是否使用了外置 Redis（`/etc/gitlab/gitlab.rb` 里 `redis['enable']`、`gitlab_rails['redis_*']` 等）
3. 若是外置 Redis：请用对应 host/port/password 的 `redis-cli` 连接（此时 `gitlab-redis-cli` 未必适用）

### 3）页面卡住、后台任务不执行，是否该 `FLUSHDB`？

通常 **不建议**。更稳妥的路径是：

1. `sudo gitlab-ctl status` 确认 `redis`、`sidekiq`、`puma` 为 `run`
2. `sudo gitlab-ctl tail sidekiq` / `sudo gitlab-ctl tail redis`
3. 必要时重启：

```bash
sudo gitlab-ctl restart sidekiq
```

4. 清理缓存（而非清空 Redis）：

```bash
sudo gitlab-rake cache:clear
```

### 4）我应该用 `gitlab-redis-cli` 还是 `gitlab-rake`？

- **清缓存、常规运维动作**：优先 `gitlab-rake` / `gitlab-ctl`
- **确认 Redis 是否存活、内存/连接/队列压力**：用 `gitlab-redis-cli` 做只读观察

## 常用命令清单（建议记住）

| 目标 | 命令 |
|------|------|
| 连通性探测 | `sudo gitlab-redis-cli PING` |
| 查看整体信息 | `sudo gitlab-redis-cli INFO` |
| 查看内存 | `sudo gitlab-redis-cli INFO memory` |
| 查看客户端 | `sudo gitlab-redis-cli INFO clients` |
| 扫描 key（安全） | `sudo gitlab-redis-cli --scan --pattern '<pattern>'` |
| 清应用缓存（推荐） | `sudo gitlab-rake cache:clear` |

## 参考链接

- [GitLab Docs - Redis](https://docs.gitlab.com/administration/redis/)
- [Redis command reference](https://redis.io/docs/latest/commands/)
