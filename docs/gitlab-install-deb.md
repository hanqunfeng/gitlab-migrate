# GitLab 安装指南（Debian / Ubuntu）

本文档介绍在 **Debian** 与 **Ubuntu LTS** 等使用 `apt` 的 DEB 系系统上安装 GitLab，涵盖 **Community Edition（CE）**、**Enterprise Edition（EE）** 与 **极狐 GitLab（JH）** 三种发行版。

> RPM 系系统（RHEL / Rocky / Amazon Linux 等）请参见 [GitLab 安装指南（RPM）](gitlab-install-rpm.md)。  
> 若你正在搭建迁移目标实例，安装完成后可参考 [README](../README.md) 使用本仓库的迁移工具。

## CE、EE 与极狐（JH）的区别与联系

三者功能定位、授权与选型说明与 RPM 版一致，详见 [gitlab-install-rpm.md 中的对比章节](gitlab-install-rpm.md#ceee-与极狐jh-的区别与联系)。

简要结论：

- **CE**：开源免费，核心 DevOps 能力。
- **EE**：未订阅时功能与 CE **基本一致**；订阅后解锁企业级能力。
- **极狐 JH**：面向国内用户，未订阅时功能与 CE **基本一致**；使用 `packages.gitlab.cn` 软件源。

DEB 系与 RPM 系的差异主要在**软件源脚本**（`script.deb.sh`）与**包管理器**（`apt`）；安装后的配置路径（`/etc/gitlab/gitlab.rb`）、管理命令（`gitlab-ctl`）完全相同。

## 支持的系统

`script.deb.sh` 通过检测 `os` 与 `dist`（发行版代号），从 `packages.gitlab.com` 拉取对应 APT 源配置，仅适用于 **APT 系** 系统。

| 发行版 | 官方支持版本 | 架构 |
|--------|--------------|------|
| Debian | 11（Bullseye）、12（Bookworm）、13（Trixie） | `amd64`、`arm64` |
| Ubuntu LTS | 20.04（Focal）、22.04（Jammy）、24.04（Noble） | `amd64`、`arm64` |

**不适用：**

- RPM 系（CentOS、Rocky、AlmaLinux、Amazon Linux 等）→ 使用 [gitlab-install-rpm.md](gitlab-install-rpm.md) 中的 `script.rpm.sh`
- 非 LTS 的 Ubuntu  interim 版本、过旧发行版
- 部分 Debian 衍生版若 GitLab 未提供对应源配置，脚本会报 *Repository configuration unavailable*

**检测失败时手动指定：**

```bash
# Debian 12 示例
curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo os=debian dist=bookworm bash

# Ubuntu 22.04 示例
curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo os=ubuntu dist=jammy bash
```

## 环境要求

| 项目 | 最低建议 |
|------|----------|
| CPU | 2 核 |
| 内存 | 4 GB（生产环境建议 8 GB 及以上） |
| 磁盘 | 20 GB 可用空间（视仓库数量增加） |
| 系统 | 64 位 Linux，支持 `apt`（见上表） |
| 网络 | CE/EE：可访问 `packages.gitlab.com`；极狐 JH：另需 `packages.gitlab.cn`、`storage.googleapis.com` |

## 安装前准备

### 1. 确定访问地址

安装时需通过 `EXTERNAL_URL` 指定 GitLab 对外访问地址：

```bash
# 使用 IP
EXTERNAL_URL="http://192.168.1.100"

# 使用域名（推荐生产环境，并配置 HTTPS）
EXTERNAL_URL="https://gitlab.example.com"
```

> `EXTERNAL_URL` 在安装时写入配置，后续修改需执行 `gitlab-ctl reconfigure`。  
> 首次安装时若 `EXTERNAL_URL` 为 `https`，GitLab 可基于 Let's Encrypt 自动签发证书（需域名可公网解析）。

### 2. 开放防火墙端口（如启用 ufw）

```bash
sudo ufw allow http
sudo ufw allow https
sudo ufw allow OpenSSH
sudo ufw enable   # 若尚未启用
sudo ufw status
```

### 3. 安装依赖

```bash
sudo apt update
sudo apt install -y curl openssh-server ca-certificates tzdata perl locales
sudo systemctl enable --now ssh
```

## 安装步骤

以下三种方式结构相同：先添加软件源，再指定 `EXTERNAL_URL` 用 `apt` 安装。将示例地址替换为你的 IP 或域名。

### 方式一：GitLab CE（社区版，默认推荐）

**步骤 1：添加 CE 软件源**

```bash
curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash
```

**步骤 2：安装 GitLab CE**

```bash
# 使用 IP
sudo EXTERNAL_URL="http://192.168.1.100" apt install -y gitlab-ce

# 或使用域名
sudo EXTERNAL_URL="https://gitlab.example.com" apt install -y gitlab-ce
```

### 方式二：GitLab EE（企业版）

**步骤 1：添加 EE 软件源**

```bash
curl --location "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh" | sudo bash
```

**步骤 2：安装 GitLab EE**

```bash
sudo EXTERNAL_URL="https://gitlab.example.com" apt install -y gitlab-ee
```

> EE 安装后需配置有效许可证（License）才能使用企业功能；**未订阅时可用功能与 CE 基本一致**。许可证在 **Admin → Subscription** 中导入。

### 方式三：极狐 GitLab JH（国内用户）

极狐使用境内软件源，国内网络下载更快。

* 国内极狐提供了基于nexus搭建的仓库地址：[https://packages.gitlab.cn/#browse/browse](https://packages.gitlab.cn/#browse/browse)

| 仓库名称            | 类型     | 包格式 | 对应操作系统                             | 是否推荐   |
| --------------- | ------ | --- | ---------------------------------- | ------ |
| amazon          | hosted | yum | Amazon Linux 2 / Amazon Linux 2023 | ✅      |
| el              | hosted | yum | RHEL / Rocky / AlmaLinux / CentOS  | ✅      |
| ubuntu-bionic   | hosted | apt | Ubuntu 18.04                       | 已过期    |
| ubuntu-focal    | hosted | apt | Ubuntu 20.04                       | 推荐     |
| ubuntu-jammy    | hosted | apt | Ubuntu 22.04                       | 推荐     |
| ubuntu-noble    | hosted | apt | Ubuntu 24.04                       | **推荐** |
| ubuntu-xenial   | hosted | apt | Ubuntu 16.04                       | 已过期    |
| debian-buster   | hosted | apt | Debian 10                          | 老版本    |
| debian-bullseye | hosted | apt | Debian 11                          | 推荐     |
| debian-bookworm | hosted | apt | Debian 12                          | 推荐     |
| debian-trixie   | hosted | apt | Debian 13                          | 最新     |
| debian-stretch  | hosted | apt | Debian 9                           | 已过期    |
| raw             | hosted | raw | 相关文件下载 ，比如仓库的认证key                            | key下载：gpg/public.gpg.key   |


**步骤 1：添加极狐软件源**

```bash
# 下载key
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://packages.gitlab.cn/repository/raw/gpg/public.gpg.key \
| gpg --dearmor \
| sudo tee /etc/apt/keyrings/gitlab.gpg >/dev/null

# 设置软件源
sudo tee /etc/apt/sources.list.d/gitlab.list >/dev/null <<EOF
deb [signed-by=/etc/apt/keyrings/gitlab.gpg] https://packages.gitlab.cn/repository/ubuntu-noble noble main
EOF

# 实际上不下载key可以进行后续的安装，只不过 apt update 时会有警告
sudo tee /etc/apt/sources.list.d/gitlab.list >/dev/null <<EOF
deb [trusted=yes] https://packages.gitlab.cn/repository/ubuntu-noble noble main
EOF



# 更新
sudo apt update

# 查询
$ apt-cache search gitlab
gitlab-jh - GitLab JH Edition (including NGINX, Postgres, Redis)
glab - commandline interface for gitlab instances
libdmx-dev - X11 Distributed Multihead extension library (development headers)
………………

# 查看最新的版本信息
$ apt show gitlab-jh
Package: gitlab-jh
Version: 19.1.1-jh.0
Priority: extra
Section: misc
Maintainer: JiHu(GitLab) <support@gitlab.cn>
Installed-Size: 4598 MB
Depends: openssh-server, perl
Conflicts: gitlab-ce, gitlab-ee, gitlab-fips, gitlab
Replaces: gitlab-ce, gitlab-ee, gitlab-fips, gitlab
Homepage: https://about.gitlab.cn/
License: MIT
Vendor: JiHu(GitLab) <support@gitlab.cn>
Download-Size: 1198 MB
APT-Sources: https://packages.gitlab.cn/repository/ubuntu-noble noble/main amd64 Packages
Description: GitLab JH Edition (including NGINX, Postgres, Redis)

# 查看有哪些可用版本
$ apt-cache madison gitlab-jh
 gitlab-jh | 19.1.1-jh.0 | https://packages.gitlab.cn/repository/ubuntu-noble noble/main amd64 Packages
 gitlab-jh | 19.1.0-jh.0 | https://packages.gitlab.cn/repository/ubuntu-noble noble/main amd64 Packages
 gitlab-jh | 19.0.3-jh.0 | https://packages.gitlab.cn/repository/ubuntu-noble noble/main amd64 Packages
 …………
```

**步骤 2：安装极狐 GitLab**

```bash
sudo EXTERNAL_URL="https://gitlab.example.com" apt install -y gitlab-jh
```

可选：安装时直接设定 root 密码与邮箱，跳过 `initial_root_password` 文件：

```bash
sudo GITLAB_ROOT_EMAIL="admin@example.com" \
     GITLAB_ROOT_PASSWORD="strongpassword" \
     EXTERNAL_URL="https://gitlab.example.com" \
     apt install -y gitlab-jh
```

> 极狐有独立许可体系；**未订阅时可用功能与 CE 基本一致**。详见 [极狐 Ubuntu 安装文档](https://gitlab.cn/docs/jh/install/package/ubuntu/)。

---

无论安装哪种版本，安装过程都会自动执行 `gitlab-ctl reconfigure`，首次配置可能需要数分钟，请耐心等待。

### 步骤 3：查看初始 root 密码

若安装时未设置 `GITLAB_ROOT_PASSWORD`，初始密码保存在：

```bash
sudo cat /etc/gitlab/initial_root_password
```

> **重要**：该文件在首次登录后 24 小时内有效，过期会被自动删除。请尽快登录并修改密码。

## 首次登录

1. 浏览器访问 `EXTERNAL_URL` 中配置的地址
2. 使用 **用户名** `root` 与初始密码登录
3. 登录后按提示修改 root 密码
4. 创建 Personal Access Token（迁移工具需要）：
   - 右上角头像 → **Edit profile** → **Access Tokens**
   - 勾选 `api`、`read_repository`、`write_repository`
   - 生成后保存 Token（只显示一次）

## 常用管理命令

```bash
sudo gitlab-ctl status
sudo gitlab-ctl reconfigure
sudo gitlab-ctl restart
sudo gitlab-ctl tail
sudo gitlab-ctl stop
sudo gitlab-ctl start
```

## 修改访问地址

```bash
sudo vim /etc/gitlab/gitlab.rb
```

修改 `external_url` 后执行：

```bash
sudo gitlab-ctl reconfigure
```

## 与迁移工具对接

```bash
cp scripts/config.example.sh scripts/config.sh
```

编辑 `scripts/config.sh`，填入 `NEW_GITLAB` 与 `NEW_TOKEN`，然后按 [README](../README.md) 执行迁移。

## 常见问题

### `script.deb.sh` 报 Repository configuration unavailable

当前 `os`/`dist` 不在 GitLab 官方支持列表中。确认 `lsb_release -a` 或 `/etc/os-release` 输出，使用上文「检测失败时手动指定」方式重试。

### 安装后无法访问 Web 页面

1. 确认 `gitlab-ctl status` 中 `nginx`、`puma` 等为 `run`
2. 检查 `ufw` 或云安全组是否放行 80/443
3. 确认 `EXTERNAL_URL` 与浏览器访问地址一致

### 忘记 root 密码

```bash
sudo gitlab-rails console -e production
```

```ruby
user = User.find_by_username('root')
user.password = 'NEW_PASSWORD'
user.password_confirmation = 'NEW_PASSWORD'
user.save!
exit
```

### `initial_root_password` 文件不存在

已超过 24 小时或安装时使用了 `GITLAB_ROOT_PASSWORD`，请用上方方式重置。

## 参考链接

- [GitLab 官方 DEB 安装总览](https://docs.gitlab.com/install/package/)
- [Ubuntu 安装文档](https://docs.gitlab.com/install/package/ubuntu/)
- [Debian 安装文档](https://docs.gitlab.com/install/package/debian/)
- [GitLab CE `script.deb.sh`](https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh)
- [极狐 Debian / Ubuntu 安装文档](https://gitlab.cn/docs/jh/install/package/debian/)
- [GitLab 配置参考 `gitlab.rb`](https://docs.gitlab.com/omnibus/settings/configuration.html)
