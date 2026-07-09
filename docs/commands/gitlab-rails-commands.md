# GitLab `gitlab-rails` 常用命令速查

本文档面向 GitLab Omnibus（RPM/DEB 安装包，如 `gitlab-ce` / `gitlab-ee` / `gitlab-jh`）部署方式，介绍 `gitlab-rails` 的常见用法：进入 Rails Console、执行 Runner 脚本，以及常见排障与安全注意事项。

> `gitlab-rails` 的核心价值是：**在已正确配置的 GitLab 生产环境中，直接执行 Rails 代码**。  
> 它非常强大，也很危险：一条命令就可能改写生产数据。请只在你明确知道后果时使用。

## 基本用法与注意事项

```bash
sudo gitlab-rails <subcommand> [args...]
```

- **强烈建议先做备份/快照**：尤其在你准备修改数据或批量修复时
- **优先只读**：能用查询解决就不要写入（例如先 `find_by`、`count`、`pluck`）
- **生产环境默认是 production**：大多数 Omnibus 环境会默认指向生产配置；如需明确指定，可用 `-e production`
- **不要把敏感信息贴到工单/群里**：Console 输出可能包含邮箱、token、密钥等

## Rails Console（交互式）

用于临时排障、查看模型数据、执行少量修复动作（谨慎）。

```bash
# 进入生产环境 console
sudo gitlab-rails console -e production
```

进入后你可以执行 Ruby/Rails 代码。几个常用的“只读”例子：

```ruby
# 查 GitLab 版本
Gitlab::VERSION

# 查 root 用户（只读）
u = User.find_by_username('root')
u&.id
u&.email
u&.state

# 统计用户数量（只读）
User.count
```

> 退出 console：输入 `exit` 或按 `Ctrl+D`。

## Rails Runner（非交互式脚本）

用于把一段 Ruby 代码以脚本方式执行，适合自动化/批量操作或收集信息（仍需谨慎）。

```bash
# 执行一段 Ruby（推荐只读）
sudo gitlab-rails runner -e production 'puts "GitLab #{Gitlab::VERSION}"'
```

### 常见只读脚本示例

```bash
# 输出 GitLab 版本
sudo gitlab-rails runner -e production 'puts Gitlab::VERSION'

# 查找指定用户名是否存在
sudo gitlab-rails runner -e production 'u=User.find_by_username("root"); puts(u ? "found: #{u.id} #{u.email} #{u.state}" : "not found")'
# 查询email对应的用户信息
sudo gitlab-rails runner '
u = User.find_by(email: "youremail@xxxx.com")
puts "ID: #{u.id}"
puts "Username: #{u.username}"
puts "Name: #{u.name}"
puts "Email: #{u.email}"
puts "State: #{u.state}"
'

# 统计活跃用户数
sudo gitlab-rails runner -e production 'puts User.active.count'
```

### “需要写入”的脚本（高风险提示）

比如重置 root 密码这类操作属于**写入**，务必确认你在正确的实例上执行：

```bash
sudo gitlab-rails runner -e production '
u = User.find_by_username("root")
raise "root not found" unless u
u.password = "NEW_PASSWORD"
u.password_confirmation = "NEW_PASSWORD"
u.save!
puts "root password updated"
'
```

> 建议优先使用 Web 管理界面或更安全的官方流程。只有在“无法登录、必须救火”的情况下才用这种方式。

## 与 `gitlab-rake` / `gitlab-ctl` 的关系

- **`gitlab-ctl`**：管理服务进程、应用配置（`reconfigure`）、查看日志（`tail`）
- **`gitlab-rake`**：执行 GitLab 官方提供的 Rake 任务（健康检查、备份/恢复、清缓存等）
- **`gitlab-rails`**：直接进入 Rails 运行时执行 Ruby/Rails 代码（Console/Runner）

一般推荐顺序：

1. 服务问题 → `gitlab-ctl status` / `gitlab-ctl tail`
2. 应用自检/备份 → `gitlab-rake gitlab:check` / `gitlab-rake gitlab:backup:*`
3. 复杂数据排障或紧急修复（谨慎） → `gitlab-rails console/runner`

## 常见排障套路

### 1）无法登录 / 权限异常

先看服务是否正常：

```bash
sudo gitlab-ctl status
sudo gitlab-ctl tail puma
```

再用 `gitlab-rails runner` 做**只读核对**：

```bash
sudo gitlab-rails runner -e production 'u=User.find_by_username("root"); puts [u&.id,u&.email,u&.state].inspect'
```

### 2）怀疑后台任务没跑（Sidekiq）

```bash
sudo gitlab-ctl status
sudo gitlab-ctl tail sidekiq
```

> 这类问题通常不需要 `gitlab-rails` 介入，除非你要检查某些记录的状态字段或排查队列相关数据（更高级场景）。

## 常用命令清单（建议记住）

| 目标 | 命令 |
|------|------|
| 进入 Rails Console | `sudo gitlab-rails console -e production` |
| 执行 Runner 脚本 | `sudo gitlab-rails runner -e production '<ruby>'` |

## 常见问题

### 1）`gitlab-rails` 找不到

- Omnibus 安装通常自带 `gitlab-rails`。若找不到：
  - 确认 GitLab 是否安装在本机
  - 尝试使用完整路径：

```bash
sudo /opt/gitlab/bin/gitlab-rails -v
```

### 2）执行 runner/console 报权限或环境错误

- 确保使用 `sudo`（需要读取 GitLab 配置与访问运行目录）
- 若你启用了外置数据库/Redis，确认连接配置与网络连通
- 结合日志定位：

```bash
sudo gitlab-ctl tail puma
sudo gitlab-ctl tail postgresql
sudo gitlab-ctl tail redis
```

## 参考链接

- [GitLab Docs - Rails console](https://docs.gitlab.com/administration/operations/rails_console/)
