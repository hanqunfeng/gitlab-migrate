# GitLab 安装指南（CE / EE / 极狐）

本文档介绍在 **RHEL / CentOS / Rocky Linux / AlmaLinux / Amazon Linux** 等使用 `dnf` 的 RPM 系系统上安装 GitLab，涵盖 **Community Edition（CE）**、**Enterprise Edition（EE）** 与 **极狐 GitLab（JH）** 三种发行版。

> 若你正在搭建迁移目标实例，安装完成后可参考 [README](../README.md) 使用本仓库的迁移工具。

## CE、EE 与极狐（JH）的区别与联系

| 维度 | GitLab CE | GitLab EE | 极狐 GitLab（JH） |
|------|-----------|-----------|-------------------|
| 全称 | Community Edition | Enterprise Edition | 极狐 GitLab（JiHu GitLab） |
| 授权 | 开源免费（MIT） | 商业授权（付费订阅） | 商业产品，面向中国市场 |
| 功能范围 | 核心 DevOps 能力：代码托管、CI/CD、Issue、MR 等 | 订阅后解锁企业级能力（高级安全扫描、合规、Geo 复制、多级审批、高级 LDAP/SAML 等） | 订阅后解锁企业级能力；另提供中文界面与境内合规支持 |
| 未订阅时 | — | **与 CE 基本一致** | **与 CE 基本一致** |
| 软件源 | `packages.gitlab.com`（gitlab-ce / gitlab-ee） | 同上 | `packages.gitlab.cn`（gitlab-jh） |
| 适用场景 | 个人、小团队、预算有限、功能需求不复杂 | 中大型企业、需安全合规与高级治理 | **国内用户**、网络访问 GitLab 国际源困难、需中文界面与本地化支持 |
| 包名 | `gitlab-ce` | `gitlab-ee` | `gitlab-jh` |

**三者联系：**

- **未订阅时的功能等价**：GitLab EE 与极狐 JH 在未购买/未激活订阅时，可用功能与 GitLab CE **基本一致**（代码托管、CI/CD、Issue、MR 等核心能力均可正常使用）；企业级高级功能需有效许可证（License）后方可启用。
- **CE 与 EE**：同一技术底座，EE 在 CE 之上叠加企业功能；安装流程、配置文件（`/etc/gitlab/gitlab.rb`）、管理命令（`gitlab-ctl`）完全一致，仅软件源与包名不同。
- **极狐（JH）**：GitLab 与极狐（JiHu）合作推出的**中国发行版**，核心架构与 GitLab 相同，但使用独立软件源与许可证体系，面向境内用户优化下载速度与本地化体验。
- **迁移兼容性**：本仓库迁移工具通过 GitLab API 工作，三种版本在 API 层面基本兼容；若源与目标版本差异较大（如 EE 专有功能），迁移后需在目标实例上重新配置对应功能。

**如何选择：**

- 一般自建、学习或中小团队 → **CE**
- 需要企业级安全、合规、高可用治理 → **EE**
- 部署在国内、访问 `packages.gitlab.com` 较慢或需中文生态 → **极狐 JH**

## 环境要求

| 项目 | 最低建议 |
|------|----------|
| CPU | 2 核 |
| 内存 | 4 GB（生产环境建议 8 GB 及以上） |
| 磁盘 | 20 GB 可用空间（视仓库数量增加） |
| 系统 | 64 位 Linux，支持 `dnf` |
| 网络 | CE/EE：可访问 `packages.gitlab.com`；极狐 JH：可访问 `packages.gitlab.cn` |

## 安装前准备

### 1. 确定访问地址

安装时需通过 `EXTERNAL_URL` 指定 GitLab 对外访问地址，支持 IP 或域名：

```bash
# 使用 IP
EXTERNAL_URL="http://192.168.1.100"

# 使用域名（推荐生产环境，并配置 HTTPS）
EXTERNAL_URL="https://gitlab.example.com"
```

> `EXTERNAL_URL` 在安装时写入配置，后续修改需执行 `gitlab-ctl reconfigure`。
> 首次安装时，如果 `EXTERNAL_URL` 是https协议，会基于` Let’s Encrypt` 自动签发证书

### 2. 开放防火墙端口（如启用 firewalld）

```bash
# HTTP
sudo firewall-cmd --permanent --add-service=http
# HTTPS（若使用域名 + 证书）
sudo firewall-cmd --permanent --add-service=https
# SSH（Git over SSH，可选）
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload
```

### 3. 安装依赖（通常由 GitLab 包自动处理）

```bash
sudo dnf install -y curl policycoreutils openssh-server perl
sudo systemctl enable --now sshd
```

## 安装步骤

以下三种安装方式**步骤结构相同**：先添加软件源，再指定 `EXTERNAL_URL` 安装对应包。将示例中的地址替换为你的 IP 或域名即可。

### 方式一：GitLab CE（社区版，默认推荐）

**步骤 1：添加 CE 软件源**

```bash
curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | sudo bash
```

**步骤 2：安装 GitLab CE**

```bash
# 使用 IP
sudo EXTERNAL_URL="http://192.168.1.100" dnf install -y gitlab-ce

# 或使用域名（推荐生产环境，并配置 HTTPS）
sudo EXTERNAL_URL="https://gitlab.example.com" dnf install -y gitlab-ce
```

### 方式二：GitLab EE（企业版）

**步骤 1：添加 EE 软件源**

```bash
curl --location "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.rpm.sh" | sudo bash
```

**步骤 2：安装 GitLab EE**

```bash
# 示例：使用 EC2 公网地址
sudo EXTERNAL_URL="http://gitlab.example.com" dnf install -y gitlab-ee
```

> EE 安装后需配置有效许可证（License）才能使用企业功能；**未订阅时可用功能与 CE 基本一致**。许可证可在 GitLab 管理后台 **Admin → Subscription** 中导入。

### 方式三：极狐 GitLab JH（国内用户）

极狐使用境内软件源 `packages.gitlab.cn`，国内网络下载更快，界面与文档提供中文支持。

**步骤 1：添加极狐软件源**

```bash
curl --location "https://packages.gitlab.cn/repository/raw/scripts/setup.sh" | sudo bash
```

**步骤 2：安装极狐 GitLab**

```bash
# 示例：使用国内 EC2 公网地址（可带或不带 http:// 前缀，建议显式写上协议）
sudo EXTERNAL_URL="http://gitlab.example.com" dnf install -y gitlab-jh
```

> 极狐 GitLab 有独立的许可与订阅体系；**未订阅时可用功能与 CE 基本一致**，订阅后解锁企业级能力。详情参见 [极狐 GitLab 官方文档](https://gitlab.cn/docs/)。

---

无论安装哪种版本，安装过程都会自动执行 `gitlab-ctl reconfigure`，首次配置可能需要数分钟，请耐心等待。

### 步骤 3：查看初始 root 密码

安装完成后，GitLab 会生成一次性初始 root 密码，保存在：

```bash
sudo cat /etc/gitlab/initial_root_password
```

输出示例：

```
Password: xxxxxxxxxxxxxxxx
```

> **重要**：该文件在首次登录后 24 小时内有效，过期会被自动删除。请尽快登录并修改密码。

## 首次登录

1. 浏览器访问 `EXTERNAL_URL` 中配置的地址（如 `http://192.168.1.100`）
2. 使用以下凭据登录：
   - **用户名**：`root`
   - **密码**：步骤 3 中查到的初始密码
3. 登录后按提示修改 root 密码
4. 创建 Personal Access Token（迁移工具需要）：
   - 右上角头像 → **Edit profile** → **Access Tokens**
   - 勾选 `api`、`read_repository`、`write_repository`
   - 生成后保存 Token（只显示一次）

## 常用管理命令

```bash
# 查看各组件状态
sudo gitlab-ctl status

# 重新加载配置（修改 /etc/gitlab/gitlab.rb 后执行）
sudo gitlab-ctl reconfigure

# 重启 GitLab
sudo gitlab-ctl restart

# 查看实时日志
sudo gitlab-ctl tail

# 停止 / 启动
sudo gitlab-ctl stop
sudo gitlab-ctl start
```

## 修改访问地址

若安装时 `EXTERNAL_URL` 填写错误，可编辑配置文件后重新加载：

```bash
sudo vim /etc/gitlab/gitlab.rb
```

找到并修改：

```ruby
external_url 'http://192.168.1.100'
```

保存后执行：

```bash
sudo gitlab-ctl reconfigure
```

## 与迁移工具对接

安装并登录新 GitLab 后，在本仓库中配置目标实例：

```bash
cp scripts/config.example.sh scripts/config.sh
```

编辑 `scripts/config.sh`，填入：

| 变量 | 示例 |
|------|------|
| `NEW_GITLAB` | `http://192.168.1.100` 或 `https://gitlab.example.com` |
| `NEW_TOKEN` | 上一步创建的 PAT |

然后按 [README](../README.md) 执行迁移步骤。

## 常见问题

### 安装后无法访问 Web 页面

1. 确认 `gitlab-ctl status` 中 `nginx`、`puma`（或 `unicorn`）等为 `run`
2. 检查防火墙是否放行 80/443 端口
3. 确认 `EXTERNAL_URL` 与浏览器访问地址一致

### 忘记 root 密码

```bash
# 进入 Rails 控制台重置
sudo gitlab-rails console -e production

# 在控制台中执行（将 NEW_PASSWORD 替换为新密码）
user = User.find_by_username('root')
user.password = 'NEW_PASSWORD'
user.password_confirmation = 'NEW_PASSWORD'
user.save!
exit
```

### `initial_root_password` 文件不存在

说明已超过 24 小时或已登录修改过密码，请使用上方「忘记 root 密码」方式重置。

### SELinux 导致异常

GitLab 安装脚本通常会处理 SELinux 策略。若遇权限问题，可临时排查：

```bash
sudo ausearch -m avc -ts recent
```

不建议在生产环境直接关闭 SELinux。

## 参考链接

- [GitLab CE 官方安装文档](https://docs.gitlab.com/install/package/amazonlinux_2023/)
- [GitLab EE 订阅与许可证](https://docs.gitlab.com/subscriptions/)
- [极狐 GitLab 安装文档](https://gitlab.cn/docs/)
- [GitLab 配置参考 `gitlab.rb`](https://docs.gitlab.com/omnibus/settings/configuration.html)
