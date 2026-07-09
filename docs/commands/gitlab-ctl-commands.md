# GitLab `gitlab-ctl` 常用命令速查

本文档面向 GitLab Omnibus（RPM/DEB 安装包，如 `gitlab-ce` / `gitlab-ee` / `gitlab-jh`）部署方式，汇总 `gitlab-ctl` 高频运维命令：查看状态、启停/重启、应用配置、查看日志、组件管理与常见排障。

> `gitlab-ctl` 是 Omnibus 的统一管理入口，底层基于 runit（或 systemd 集成）管理 GitLab 各组件进程，并提供日志与诊断能力。  
> 若你使用容器化（Docker/Helm/K8s），通常需要通过容器命令或 Helm 工具管理服务，而不是 `gitlab-ctl`。

## 基本用法与注意事项

```bash
sudo gitlab-ctl <command> [args...]
```

- **修改配置**：编辑 `/etc/gitlab/gitlab.rb` 后，务必执行 `sudo gitlab-ctl reconfigure`
- **不要用 systemctl 逐个管组件**：Omnibus 的组件由 `gitlab-ctl` 统一编排，直接 `systemctl restart nginx` 这类操作可能导致状态不一致
- **遇到异常先看日志**：优先 `sudo gitlab-ctl tail`，再结合 `sudo gitlab-rake gitlab:check`

## 状态查看与基础信息

### 查看所有组件状态（最常用）

```bash
sudo gitlab-ctl status
```

你会看到 `run` / `down` 等状态，常见关注点：

| 服务                    | 作用                      | 是否核心  | 说明                                         |
| --------------------- | ----------------------- | ----- | ------------------------------------------ |
| **nginx**             | Web 入口代理                | ⭐⭐⭐⭐⭐ | 接收 HTTP/HTTPS 请求，转发给 GitLab Workhorse/Puma |
| **gitlab-workhorse**  | GitLab 高性能反向代理          | ⭐⭐⭐⭐⭐ | 处理 Git HTTP、文件上传、大文件传输，减轻 Rails 压力         |
| **puma**              | GitLab Rails Web 应用服务器  | ⭐⭐⭐⭐⭐ | 运行 GitLab 主程序（Ruby on Rails）               |
| **sidekiq**           | 后台任务处理                  | ⭐⭐⭐⭐⭐ | 执行异步任务，如邮件、Pipeline、Repository 操作          |
| **gitaly**            | Git 仓库服务                | ⭐⭐⭐⭐⭐ | GitLab 自研 Git RPC 服务，管理 Repository 读写      |
| **postgresql**        | 数据库                     | ⭐⭐⭐⭐⭐ | 存储用户、项目、权限、Issue、MR 等元数据                   |
| **redis**             | 缓存和队列                   | ⭐⭐⭐⭐⭐ | 保存缓存、Session、Sidekiq 队列                    |
| **gitlab-kas**        | Kubernetes Agent Server | ⭐⭐⭐   | GitLab Kubernetes Agent 服务，用于 GitOps       |
| **alertmanager**      | 告警管理                    | ⭐⭐    | 接收 Prometheus 告警并通知                        |
| **prometheus**        | 监控数据采集                  | ⭐⭐    | GitLab 自带监控系统                              |
| **node-exporter**     | 主机指标采集                  | ⭐⭐    | 收集 CPU、内存、磁盘等系统指标                          |
| **gitlab-exporter**   | GitLab 指标采集             | ⭐⭐    | 提供 GitLab 内部指标给 Prometheus                 |
| **postgres-exporter** | PostgreSQL 指标采集         | ⭐⭐    | 收集数据库性能指标                                  |
| **redis-exporter**    | Redis 指标采集              | ⭐⭐    | 收集 Redis 性能指标                              |
| **logrotate**         | 日志轮转                    | ⭐⭐⭐   | 定期压缩、删除旧日志                                 |


### 输出当前配置摘要（排障有用）

```bash
sudo gitlab-ctl show-config
```

> 注：输出较长，适合在排查“配置到底生效没”时使用。

## 启动、停止与重启

### 启停整个 GitLab

```bash
sudo gitlab-ctl stop
sudo gitlab-ctl start
sudo gitlab-ctl restart
```

### 启停/重启单个组件

```bash
sudo gitlab-ctl restart puma
sudo gitlab-ctl restart sidekiq
sudo gitlab-ctl restart nginx
sudo gitlab-ctl restart gitaly
sudo gitlab-ctl restart postgresql
sudo gitlab-ctl restart redis
```

### 优雅重启（尽量减少中断）

```bash
sudo gitlab-ctl hup puma
sudo gitlab-ctl hup nginx
```

> 说明：`hup` 通常用于重新加载配置或日志切换等场景；是否支持/效果取决于组件实现与版本。

## 应用配置：`reconfigure`（非常重要）

当你修改了 `/etc/gitlab/gitlab.rb`（例如 `external_url`、SMTP、HTTPS 证书路径、外置数据库/Redis 等）之后，需要执行：

```bash
sudo gitlab-ctl reconfigure
```

常见用途：

- **首次安装后**：检查配置是否正确并确保服务拉起
- **调整 `external_url` / 证书 / SMTP / LDAP** 等
- **升级后**：包安装通常会自动触发 reconfigure，但失败时需要人工介入

> 注意：`reconfigure` 会执行 Chef/配置编排，可能重写部分配置文件并触发服务重启，建议在低峰执行。

## 日志查看与诊断

### 实时查看所有日志（快速定位）

```bash
sudo gitlab-ctl tail
```

### 查看指定组件日志

```bash
sudo gitlab-ctl tail puma
sudo gitlab-ctl tail sidekiq
sudo gitlab-ctl tail nginx
sudo gitlab-ctl tail gitaly
sudo gitlab-ctl tail postgresql
sudo gitlab-ctl tail redis
```

### 常见“先看哪一个”

- **页面 502/504**：先看 `nginx` + `puma`
- **页面操作卡住/一直转圈、异步任务不跑**：看 `sidekiq`
- **git clone/push 失败、仓库不可用**：看 `gitaly` + `puma`
- **登录/会话异常**：看 `puma`，并检查 `redis`


## 常见排障套路（实用）

### 1）Web 可访问但功能异常

```bash
sudo gitlab-ctl status
sudo gitlab-ctl tail sidekiq
sudo gitlab-rake gitlab:check
```

常见根因：`sidekiq` down、Redis 异常、数据库连接问题。

### 2）502 / 504 / 页面打不开

```bash
sudo gitlab-ctl status
sudo gitlab-ctl tail nginx
sudo gitlab-ctl tail puma
```

常见根因：`puma` 启动失败（内存不足、迁移未完成、配置错误）、反代端口/证书配置错误。

### 3）git clone/push 失败（HTTP/SSH）

```bash
sudo gitlab-ctl status
sudo gitlab-ctl tail gitaly
sudo gitlab-ctl tail puma
sudo gitlab-ctl tail nginx
```

常见根因：Gitaly 存储/权限问题、磁盘满、Nginx/Workhorse 限制、SSH 端口/证书问题。

## 常用命令清单（建议记住）

| 目标 | 命令 |
|------|------|
| 查看整体状态 | `sudo gitlab-ctl status` |
| 重启整个 GitLab | `sudo gitlab-ctl restart` |
| 重启 Web/队列 | `sudo gitlab-ctl restart puma` / `sudo gitlab-ctl restart sidekiq` |
| 应用配置变更 | `sudo gitlab-ctl reconfigure` |
| 看所有日志 | `sudo gitlab-ctl tail` |
| 看组件日志 | `sudo gitlab-ctl tail <service>` |

## 常见问题

### 1）`gitlab-ctl` 找不到

- Omnibus 安装通常自带 `gitlab-ctl`。若系统提示找不到：
  - 确认 GitLab 是否安装在本机
  - 尝试使用完整路径：

```bash
sudo /opt/gitlab/bin/gitlab-ctl status
```

### 2）`reconfigure` 失败怎么办

建议顺序：

1. 先看输出末尾的错误信息（通常包含具体组件与配置项）
2. 看日志（如果是服务启动失败）：

```bash
sudo gitlab-ctl tail
```

3. 再次确认 `/etc/gitlab/gitlab.rb` 的配置项是否拼写/路径正确（证书路径、外置数据库连接等）


