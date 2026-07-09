# GitLab `gitlab-rake` 常用命令速查

本文档介绍 GitLab Omnibus（RPM/DEB 安装包）场景下常用的 `gitlab-rake` 维护命令，覆盖日常巡检、备份、缓存/队列、升级与常见排障。

> `gitlab-rake` 本质上是对 GitLab Rails Rake Task 的封装，等价于在生产环境执行 `bundle exec rake ...`。  
> 若你使用的是源码安装（self-compiled）或容器化部署（如 Helm/K8s），命令入口与执行方式可能不同，请以对应部署方式文档为准。

## 基本用法与注意事项

### 命令入口

```bash
# Omnibus 安装（推荐）
sudo gitlab-rake <task> [KEY=VALUE ...]

# 另一种常见入口：gitlab-rails（本质也是 Rails 环境）
sudo gitlab-rails runner 'puts "hello"'
sudo gitlab-rails console -e production
```

### 运行前的通用建议

- **尽量在低峰期执行**：部分任务会触发大量 DB/Redis/Sidekiq 操作，可能影响性能。
- **先确认实例状态**：必要时先执行 `sudo gitlab-ctl status` 与 `sudo gitlab-rake gitlab:check`。
- **谨慎对待清理类任务**：带 `cleanup` / `prune` / `delete` / `truncate` 的任务可能不可逆。
- **备份相关优先保证磁盘空间**：备份文件通常位于 `/var/opt/gitlab/backups/`（可在 `gitlab.rb` 中配置）。

## 巡检与健康检查

### 环境与版本信息

```bash
# 输出 GitLab 环境信息（版本、组件、配置摘要等）
sudo gitlab-rake gitlab:env:info

# 基础诊断：数据库、Redis、Sidekiq、存储等检查
sudo gitlab-rake gitlab:check

# 更“严格”的检查：会做更多一致性校验（耗时更长）
sudo gitlab-rake gitlab:check SANITIZE=true
```

常见用途：

- **升级/迁移后自检**：安装、升级、恢复备份后第一时间跑一遍。
- **排查“页面能打开但功能异常”**：例如 Sidekiq/Redis/存储不可用。

## 备份与恢复（重点）

> GitLab 备份通常包含数据库与仓库等数据，但**并不必然包含**所有配置与密钥。Omnibus 下强烈建议额外备份 `/etc/gitlab/` 与关键密钥文件（见下文）。

### 创建备份

```bash
# 创建备份（会写入 /var/opt/gitlab/backups/）
sudo gitlab-rake gitlab:backup:create

# 跳过构件/上传等（按需）
sudo gitlab-rake gitlab:backup:create SKIP=artifacts,uploads
```

### 查看与校验备份

```bash
sudo ls -lh /var/opt/gitlab/backups/
# 输出
total 832K
-rw-------. 1 git git 830K Jul  8 07:19 1783495135_2026_07_08_19.1.1_gitlab_backup.tar
```

> 说明：备份文件名一般带有时间戳与版本信息。不同版本命名略有差异，以实际生成文件为准。

### 恢复备份（高风险，务必谨慎）

恢复通常需要：

1. **停掉会写入数据的服务**（尤其 `puma`/`sidekiq` 等）
2. 执行恢复任务（指定时间戳）
3. 重启并执行检查

示例（以实际提示为准）：

```bash
sudo gitlab-ctl stop puma
sudo gitlab-ctl stop sidekiq

# 假设要回复为备份文件名称为 1783495135_2026_07_08_19.1.1_gitlab_backup.tar
sudo gitlab-rake gitlab:backup:restore BACKUP=1783495135_2026_07_08_19.1.1
# 此时会有两次询问你是否继续，输入 yes 则继续
Do you want to continue (yes/no)? yes

sudo gitlab-ctl restart
sudo gitlab-rake gitlab:check
```

### 备份之外必须保留的关键文件

Omnibus 下强烈建议同时备份：

- **配置目录**：`/etc/gitlab/`（尤其 `gitlab.rb`、`gitlab-secrets.json`）
- **SSH 主机密钥**（若有自定义）：`/etc/ssh/ssh_host_*`
- **TLS 证书/私钥**（若使用自签或自管证书）：通常在 `/etc/gitlab/ssl/` 或你自定义的路径

否则即便恢复了备份，仍可能出现：

- CI Runner、WebHook、OAuth、加密数据无法解密
- LDAP/SAML/SMTP 等配置丢失
- 证书变更导致客户端不信任

## 缓存、会话与常见“清一清”操作

### 清理 Rails 缓存（解决部分页面异常/升级后缓存问题）

```bash
sudo gitlab-rake cache:clear
```

### 清理 Redis cache（按需）

```bash
sudo gitlab-rake cache:clear:redis
```

> 注意：缓存类清理通常安全，但可能导致短期性能抖动（缓存重建）。

## 侧边队列（Sidekiq）与后台任务

`gitlab-rake` 里部分任务会依赖 Sidekiq 执行异步作业；当你遇到“页面操作卡住/一直转圈”“MR/Issue 状态不更新”等问题时，优先检查 Sidekiq：

```bash
sudo gitlab-ctl status
sudo gitlab-ctl tail sidekiq
```

必要时可重启：

```bash
sudo gitlab-ctl restart sidekiq
```

> 提示：很多“rake 任务没报错但结果没生效”，根因是 Sidekiq 没有正常消费队列。

## 数据库迁移与升级相关

### 重新配置与重启（最常用）

```bash
# 修改 /etc/gitlab/gitlab.rb 后应用配置
sudo gitlab-ctl reconfigure

# 重启服务
sudo gitlab-ctl restart
```

### 数据库迁移（一般升级包会自动做）

多数情况下你不需要手动跑迁移；但在升级/恢复/特殊故障场景下，可能会看到 GitLab 提示运行迁移任务。常见的入口仍然是 `gitlab-rake`：

```bash
sudo gitlab-rake db:migrate
```

> 注意：`db:migrate` 属于高风险操作，务必先做快照/备份，并确保与你安装的 GitLab 版本匹配。

## 项目/仓库相关排障

当出现仓库读取异常、Gitaly 报错、Git 操作失败等情况时，建议结合以下命令分层定位：

```bash
# GitLab 侧基础自检
sudo gitlab-rake gitlab:check

# 服务状态与日志
sudo gitlab-ctl status
sudo gitlab-ctl tail gitaly
sudo gitlab-ctl tail puma
sudo gitlab-ctl tail nginx
```

## 日常运维推荐掌握的命令

对于 GitLab 管理员来说，以下命令是最常用的一组：

| 功能           | 命令                                                     |
| ------------ | ------------------------------------------------------ |
| 系统健康检查       | `sudo gitlab-rake gitlab:check SANITIZE=true`          |
| 查看环境信息       | `sudo gitlab-rake gitlab:env:info`                     |
| 创建备份         | `sudo gitlab-rake gitlab:backup:create`                |
| 恢复备份         | `sudo gitlab-rake gitlab:backup:restore BACKUP=<备份ID>` |
| 查看数据库迁移状态    | `sudo gitlab-rake db:migrate:status`                   |
| 执行数据库迁移      | `sudo gitlab-rake db:migrate`                          |
| 清理缓存         | `sudo gitlab-rake cache:clear`                         |
| 清理临时文件       | `sudo gitlab-rake tmp:clear`                           |
| 检查仓库完整性      | `sudo gitlab-rake gitlab:git:fsck`                     |
| 查看所有 Rake 任务 | `sudo gitlab-rake -T`                                  |

### 批量把用户加入其可访问的项目（迁移辅助）

在迁移/导出脚本需要“用某个用户的 token 拉取项目列表”但又发现 **API 返回的项目不全** 时（即便该用户在 Web UI 中是管理员，旧版 GitLab 的某些 API 行为也可能仅返回“用户已被授予的项目”），可用以下任务将指定邮箱对应的用户批量加入其相关项目，以提升可见性，但如果是管理员就没必要这么做，通过API接口`/api/v4/projects/all` 一样可以获取全部项目信息。

```bash
sudo gitlab-rake gitlab:import:user_to_projects[youremail@domain.com]
```

注意事项：

- 该命令会**修改生产数据（成员关系）**，建议在低峰期执行，并在执行前做好备份/快照。
- 项目数量较多时可能触发大量数据库写入与后台任务（Sidekiq），若执行后未生效请检查 Sidekiq 是否正常。
- 若你能使用 **管理员级别的 API Token** 完成迁移，通常更推荐“用管理员 token 读取全量项目 + 迁移到新实例后再同步成员”，而不是在旧实例上做大规模授权变更。

## 常见问题

### 1）提示找不到命令 `gitlab-rake`

- Omnibus 安装通常自带 `gitlab-rake`。若找不到：
  - 确认 GitLab 是否安装在本机
  - 尝试使用完整路径（不同系统可能在 `/opt/gitlab/bin/gitlab-rake`）

```bash
sudo /opt/gitlab/bin/gitlab-rake gitlab:env:info
```

### 2）执行任务很慢或卡住

- 先看资源：CPU/内存/磁盘/IO 是否充足
- 看日志：

```bash
sudo gitlab-ctl tail
```

- 若涉及备份/恢复/迁移：确认磁盘空间、数据库连接、Sidekiq 是否正常

## 参考链接

- [GitLab Docs - Rake tasks](https://docs.gitlab.com/administration/raketasks/)
- [GitLab Docs - Backup and restore](https://docs.gitlab.com/administration/backup_restore/)
