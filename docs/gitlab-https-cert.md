# GitLab 配置 HTTPS 证书指南

本文档介绍在 **Omnibus 安装的 GitLab CE/EE** 上配置 HTTPS 证书（GitLab 内置 Nginx），使 Web 访问与 Git over HTTP 均走 TLS。

> 若尚未安装 GitLab，请先参考 [GitLab 安装指南](gitlab-install.md)。

## 方案选择

常见有两种方式：

- **Let’s Encrypt（推荐，公网可访问域名）**：证书自动签发与续期，维护成本低。
- **自签名 / 内网 CA / 已有证书（内网/私有域名）**：需要你自行准备证书文件，客户端可能需要导入根证书或跳过校验。

> GitLab Omnibus 的 HTTPS 配置主要在 `/etc/gitlab/gitlab.rb`，修改后必须执行 `sudo gitlab-ctl reconfigure` 生效。

## 前置条件

- 已准备好对外访问地址（域名更推荐），例如 `gitlab.example.com`
- DNS 已解析到 GitLab 服务器
- 防火墙 / 安全组已放行：
  - **80**（Let’s Encrypt HTTP-01 验证需要；也可配置为仅签发阶段临时放行）
  - **443**（HTTPS 服务）

在服务器上确认端口：

```bash
sudo ss -lntp | egrep '(:80|:443)\b' || true
```

## 方式一：使用 Let’s Encrypt 自动签发（推荐）

适用场景：**域名公网可访问**（Let’s Encrypt 能从公网访问到你的 80 端口）。

### 步骤 1：设置 external_url 为 https

编辑配置：

```bash
sudo vim /etc/gitlab/gitlab.rb
```

设置（将域名替换为你自己的）：

```ruby
external_url 'https://gitlab.example.com'
```

### 步骤 2：启用 Let’s Encrypt

在 `/etc/gitlab/gitlab.rb` 中追加或修改：

```ruby
letsencrypt['enable'] = true
letsencrypt['contact_emails'] = ['admin@example.com']

# 可选：让 GitLab/Nginx 自动把 HTTP 跳转到 HTTPS
nginx['redirect_http_to_https'] = true
```

### 步骤 3：应用配置并观察签发结果

```bash
sudo gitlab-ctl reconfigure
```

签发成功后通常会看到类似证书路径的输出；你也可以检查证书目录是否生成：

```bash
sudo ls -l /etc/gitlab/ssl/ || true
```

### 步骤 4：验证 HTTPS

```bash
curl -I "https://gitlab.example.com" | head -n 5
```

浏览器访问 `https://gitlab.example.com`，应显示锁标识且证书链可信。

### 续期说明

Omnibus 默认会配置续期计划任务。若你需要手动触发续期（排障/验证），可执行：

```bash
sudo gitlab-ctl renew-le-certs
```

## 方式二：使用自有证书（自签名 / 内网 CA / 现成证书）

适用场景：内网域名、离线环境、公司 CA、或你已经有 PEM 证书。

### 证书文件要求

GitLab Omnibus（Nginx）通常使用 PEM 文件：

- **证书**：`*.crt` 或 `*.pem`（包含服务端证书；如有中间证书链，建议拼接成 fullchain）
- **私钥**：`*.key`

建议命名（以域名为名，便于维护）：

- `/etc/gitlab/ssl/gitlab.example.com.crt`
- `/etc/gitlab/ssl/gitlab.example.com.key`

> 注意：证书里的 **CN/SAN 必须包含你访问用的域名**，否则浏览器会提示域名不匹配。

### 步骤 1：放置证书到 /etc/gitlab/ssl

创建目录（若不存在）：

```bash
sudo mkdir -p /etc/gitlab/ssl
```

把你的证书与私钥拷贝到该目录（自行替换源文件路径）：

```bash
sudo cp /path/to/gitlab.example.com.crt /etc/gitlab/ssl/
sudo cp /path/to/gitlab.example.com.key /etc/gitlab/ssl/
```

设置权限（非常重要，避免 Nginx 读取失败或私钥泄露）：

```bash
sudo chown root:root /etc/gitlab/ssl/gitlab.example.com.*
sudo chmod 600 /etc/gitlab/ssl/gitlab.example.com.key
sudo chmod 644 /etc/gitlab/ssl/gitlab.example.com.crt
```

### 步骤 2：配置 external_url 与 Nginx 证书路径

编辑 `/etc/gitlab/gitlab.rb`：

```bash
sudo vim /etc/gitlab/gitlab.rb
```

追加或修改：

```ruby
external_url 'https://gitlab.example.com'

nginx['redirect_http_to_https'] = true
nginx['ssl_certificate'] = "/etc/gitlab/ssl/gitlab.example.com.crt"
nginx['ssl_certificate_key'] = "/etc/gitlab/ssl/gitlab.example.com.key"
```

### 步骤 3：应用配置

```bash
sudo gitlab-ctl reconfigure
```

### 步骤 4：验证

```bash
curl -Iv "https://gitlab.example.com" 2>&1 | egrep -i 'subject:|issuer:|SSL connection|verify' | head -n 20
```

若是自签名/内网 CA，客户端可能会显示 `self signed certificate` 或 `unable to get local issuer certificate`，这属于预期，需要在客户端导入 CA 根证书或配置企业信任链。

## 常见问题

### 1）浏览器提示“证书不受信任”

- Let’s Encrypt：检查域名是否公网可访问、80 端口是否可达、DNS 是否解析正确；必要时查看 reconfigure 日志或 GitLab Nginx 日志。
- 自签名/内网 CA：需要在客户端（浏览器/系统）导入公司根证书，或使用公司 CA 签发的证书链。

### 2）访问 https 后 502 / 503

优先排查 GitLab 服务状态：

```bash
sudo gitlab-ctl status
sudo gitlab-ctl tail nginx
sudo gitlab-ctl tail puma
```

若 `nginx` 日志提示无法读取私钥，通常是证书路径或权限问题（确保 `.key` 为 `600` 且属主为 `root`）。

### 3）HTTP 没跳转到 HTTPS

确认 `/etc/gitlab/gitlab.rb` 中开启：

```ruby
nginx['redirect_http_to_https'] = true
```

修改后执行 `sudo gitlab-ctl reconfigure`。

### 4）Git clone / push 走 HTTPs 报证书错误

- 公网证书：确认系统时间正确、证书链完整。
- 自签名/内网 CA：需要在开发机导入 CA 根证书；不要长期使用 `GIT_SSL_NO_VERIFY=true` 这类跳过校验的方式。

## 参考链接

- [GitLab 官方：TLS/SSL（Omnibus）](https://docs.gitlab.com/omnibus/settings/ssl/)
- [GitLab 官方：Let’s Encrypt（Omnibus）](https://docs.gitlab.com/omnibus/settings/ssl/#enable-the-lets-encrypt-integration)

