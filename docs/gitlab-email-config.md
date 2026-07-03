# GitLab 邮件功能配置指南

本文档介绍在 **Omnibus 安装的 GitLab CE** 上配置 SMTP 发信，使 GitLab 能够发送通知邮件、密码重置邮件、流水线结果通知等。

> 若尚未安装 GitLab，请先参考 [RPM 系安装指南](gitlab-install-rpm.md) 或 [Debian/Ubuntu 安装指南](gitlab-install-deb.md)。

## 为什么需要配置邮件

GitLab 默认不会自动发信。未配置 SMTP 时，以下功能会受影响：

| 场景 | 说明 |
|------|------|
| 密码重置 | 用户点击「忘记密码」后收不到邮件 |
| 系统通知 | Issue / MR 指派、评论、@提及等通知无法送达 |
| 流水线通知 | CI/CD 失败、合并请求状态变更等 |
| 新用户邀请 | 管理员创建用户后无法通过邮件发送初始凭据 |

迁移工具创建用户时虽设置了 `reset_password=true`，但若未配置邮件，用户仍需管理员在后台手动重置密码。

## 配置概览

GitLab Omnibus 的邮件相关配置集中在 `/etc/gitlab/gitlab.rb`，修改后需执行 `gitlab-ctl reconfigure` 生效。

主要涉及两类设置：

1. **SMTP 连接**：如何连接邮件服务器
2. **发件人信息**：邮件中显示的 From / Reply-To 地址

## 通用配置步骤

### 步骤 1：准备 SMTP 信息

向邮件服务商或 IT 部门获取以下信息：

| 参数 | 说明 |
|------|------|
| SMTP 地址 | 如 `smtp.163.com`、`smtp.qq.com` |
| 端口 | 常见：465（SSL）、587（STARTTLS）、25 |
| 用户名 | 通常为完整邮箱地址 |
| 密码 / 授权码 | 多数邮箱需使用「授权码」，而非登录密码 |
| 加密方式 | SSL/TLS 或 STARTTLS |
| 发件地址 | 与 SMTP 用户名一致的邮箱地址 |

### 步骤 2：编辑配置文件

```bash
sudo vim /etc/gitlab/gitlab.rb
```

在文件末尾追加 SMTP 配置（以下为通用模板，请按实际服务商修改）：

```ruby
### SMTP 发信配置
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "smtp.example.com"
gitlab_rails['smtp_port'] = 587
gitlab_rails['smtp_user_name'] = "gitlab@example.com"
gitlab_rails['smtp_password'] = "YOUR_SMTP_PASSWORD_OR_AUTH_CODE"
gitlab_rails['smtp_domain'] = "example.com"
gitlab_rails['smtp_authentication'] = "login"
gitlab_rails['smtp_enable_starttls_auto'] = true
gitlab_rails['smtp_tls'] = false
gitlab_rails['smtp_openssl_verify_mode'] = 'peer'

### 发件人信息
gitlab_rails['gitlab_email_from'] = 'gitlab@example.com'
gitlab_rails['gitlab_email_reply_to'] = 'noreply@example.com'
```

> **安全提示**：`gitlab.rb` 中含 SMTP 密码，请限制文件权限（默认 root 可读），勿将含密码的配置提交到版本库。

### 步骤 3：应用配置

```bash
sudo gitlab-ctl reconfigure
```

该命令会重新生成 GitLab 各组件配置并重启相关服务，通常需要 1～3 分钟。

### 步骤 4：发送测试邮件

```bash
sudo gitlab-rails console -e production
```

在 Rails 控制台中执行（将邮箱地址替换为可收件的真实地址）：

```ruby
Notify.test_email('your@email.com', 'GitLab 邮件测试', '如果你收到这封邮件，说明 SMTP 配置成功。').deliver_now
```
* 示例
```ruby
$ sudo gitlab-rails console
--------------------------------------------------------------------------------
 Ruby:         ruby 3.3.11 (2026-03-26 revision 1f2d15125a) [x86_64-linux]
 GitLab:       19.1.1 (04cd8ad1a9c) FOSS
 GitLab Shell: 14.54.0
 PostgreSQL:   17.8
------------------------------------------------------------[ booted in 54.10s ]
Loading production environment (Rails 7.2.3.1)
gitlab(prod)> Notify.test_email('hqf123456@163.com','test','hello world').deliver_now
=> #<Mail::Message:1038020, Multipart: false, Headers: <Date: Thu, 02 Jul 2026 02:34:53 +0000>, <From: GitLab <1861345678@163.com>>, <Reply-To: GitLab <noreply@163.com>>, <To: hqf123456@163.com>, <Message-ID: <6a45ce4d989a_465e433541806e@ip-172-31-26-12.us-west-2.compute.internal.mail>>, <Subject: test>, <MIME-Version: 1.0>, <Content-Type: text/html; charset=UTF-8>, <Content-Transfer-Encoding: 7bit>, <Auto-Submitted: auto-generated>, <X-Auto-Response-Suppress: All>>
gitlab(prod)> exit
```

- 返回对象且无异常，表示 GitLab 已将邮件交给 SMTP 服务器
- 执行 `exit` 退出控制台

若未收到邮件，请检查垃圾箱，并参考下文 [常见问题](#常见问题)。

## 常见邮件服务商示例

### 网易 163 邮箱
> 163 邮箱本人亲测可用，其它邮箱未进行测试

163 邮箱需先在网页端开启 SMTP 并生成**授权码**（设置 → POP3/SMTP/IMAP）。

```ruby
# 启用邮件发送
gitlab_rails['smtp_enable'] = true

# SMTP 服务器配置（适用于网易邮箱）
gitlab_rails['smtp_address'] = "smtp.163.com"  # 网易邮箱的 SMTP 服务器地址
gitlab_rails['smtp_port'] = 465
gitlab_rails['smtp_user_name'] = "yourname@163.com"  # 你的网易邮箱地址
gitlab_rails['smtp_password'] = "YOUR_163_AUTH_CODE"  # 你的网易邮箱授权码
gitlab_rails['smtp_domain'] = "163.com"  # 网易邮箱域名
gitlab_rails['smtp_authentication'] = "login"  # 认证方式：login
gitlab_rails['smtp_enable_starttls_auto'] = false  # 启用 STARTTLS
gitlab_rails['smtp_tls'] = true  # 使用 SSL 加密
gitlab_rails['smtp_pool'] = false  # 禁用连接池

# 注意发件人不要写成 'GitLab <yourname@163.com>' 这种格式，否则重置密码邮件会发送失败
gitlab_rails['gitlab_email_from'] = 'yourname@163.com' # 发件人地址，此处的email必须要与smtp_user_name配置的一致
gitlab_rails['gitlab_email_reply_to'] = 'yourname@your-domain.com' # 回复邮件地址
```


#### 163 开启 SMTP时要注意
* 1.开起 SMTP 时，需要在 `设置` -- `邮箱安全设置` -- `安全性活动` 中对该操作进行确认
* 2.新注册的用户开通 SMTP 后配置到第三方中可能还会提示认证失败，这可能是网易的安全管控，可以在浏览器端收发几封邮件，并等待24小时后在进行测试。

### 腾讯 QQ 邮箱

同样需开启 SMTP 并使用授权码。

```ruby
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "smtp.qq.com"
gitlab_rails['smtp_port'] = 465
gitlab_rails['smtp_user_name'] = "yourname@qq.com"
gitlab_rails['smtp_password'] = "YOUR_QQ_AUTH_CODE"
gitlab_rails['smtp_domain'] = "qq.com"
gitlab_rails['smtp_authentication'] = "login"
gitlab_rails['smtp_enable_starttls_auto'] = false
gitlab_rails['smtp_tls'] = true
gitlab_rails['smtp_openssl_verify_mode'] = 'peer'

gitlab_rails['gitlab_email_from'] = 'GitLab <yourname@qq.com>'
gitlab_rails['gitlab_email_reply_to'] = 'yourname@qq.com'
```

### 企业邮箱 / 自建邮件服务器

以端口 587 + STARTTLS 为例（Exchange、阿里企业邮等常见）：

```ruby
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "smtp.company.com"
gitlab_rails['smtp_port'] = 587
gitlab_rails['smtp_user_name'] = "gitlab@company.com"
gitlab_rails['smtp_password'] = "YOUR_PASSWORD"
gitlab_rails['smtp_domain'] = "company.com"
gitlab_rails['smtp_authentication'] = "login"
gitlab_rails['smtp_enable_starttls_auto'] = true
gitlab_rails['smtp_tls'] = false
gitlab_rails['smtp_openssl_verify_mode'] = 'peer'

gitlab_rails['gitlab_email_from'] = 'GitLab <gitlab@company.com>'
gitlab_rails['gitlab_email_reply_to'] = 'noreply@company.com'
```

若企业邮使用 465 端口直连 SSL，将 `smtp_port` 改为 `465`，并设置：

```ruby
gitlab_rails['smtp_enable_starttls_auto'] = false
gitlab_rails['smtp_tls'] = true
```

### 端口与加密方式对照

| 端口 | 典型用法 | `smtp_tls` | `smtp_enable_starttls_auto` |
|------|----------|------------|------------------------------|
| 465 | 隐式 SSL（SMTPS） | `true` | `false` |
| 587 | STARTTLS | `false` | `true` |
| 25 | 明文或 STARTTLS（部分内网） | `false` | 视服务商而定 |

配置组合错误是最常见的失败原因，请与邮件服务商文档核对。

## 管理后台补充设置

SMTP 配置完成后，可在 Web 界面进一步调整：

1. 以管理员登录 GitLab
2. 进入 **Admin Area**（扳手图标）→ **Settings** → **General**
3. 展开 **Email** 相关选项，我当前安装的`v19.1.1`版本在 **New user account restrictions** -- **电子邮件确认设置** 中选择 **高级设置**，这样创建新用户时就可以自动发送设置密码的邮件了。

普通用户可在 **Preferences → Notifications** 中设置个人通知偏好；若 SMTP 未配置，偏好设置不会生效。

## 验证迁移场景

配置邮件后，可验证用户迁移相关流程：

1. 执行 `./gitlab-migrate-users.sh 2` 创建用户
2. 新用户应收到「设置密码」邮件（`reset_password=true`）
3. 若仍无邮件，在 Admin → **Users** 中手动对该用户执行 **Send reset password email**

## 常见问题

### 测试邮件报错：`Connection refused` 或 `Timeout`

1. 确认 GitLab 服务器能访问 SMTP 地址和端口：

   ```bash
   nc -zv smtp.163.com 465
   ```

2. 检查防火墙、安全组是否放行出站 SMTP 端口
3. 部分云厂商默认封禁 25 端口，可改用 465 或 587

### 测试邮件报错：`535 Authentication failed`

1. 确认使用的是**授权码**而非邮箱登录密码（163 / QQ 等）
2. 检查 `smtp_user_name` 是否为完整邮箱地址
3. 确认 SMTP 服务已在邮箱网页端开启
4. 新注册的网易邮箱帐号，可能存在安全管控，可以在网页端收发几封邮件并等待24小时后再测试
5. 先验证网易 SMTP 是否真的接受这个账号
```bash
openssl s_client -connect smtp.163.com:465 -crlf -quiet
看到：

220 smtp.163.com ESMTP

以后，输入（每行输完按一次 Enter）：
EHLO test

然后继续输入：

AUTH LOGIN

等待服务器返回，输入用户名 Base64，`echo -n "yourname@163.com" | base64`
xxxxxx

等待服务器返回，输入授权码 Base64
xxxxxx

若认证成功会输出 Authentication successful
```
一个完整的示例
```bash
$ openssl s_client -connect smtp.163.com:465 -crlf -quiet
Connecting to 103.129.252.45
depth=2 C=US, O=DigiCert Inc, OU=www.digicert.com, CN=DigiCert Global Root G2
verify return:1
depth=1 C=US, O=DigiCert, Inc., CN=GeoTrust G2 TLS CN RSA4096 SHA256 2022 CA1
verify return:1
depth=0 C=CN, ST=Zhejiang, L=Hangzhou, O=NetEase (Hangzhou) Network Co., Ltd, CN=*.163.com
verify return:1
220 163.com Anti-spam GT for Coremail System (163com[20141201])
EHLO test
250-mail
250-AUTH LOGIN PLAIN XOAUTH2
250-AUTH=LOGIN PLAIN XOAUTH2
250-coremail 1Uxr2xKj7kG0xkI17xGrU7I0s8FY2U3Uj8Cz28x1UUUUU7Ic2I0Y2UFcZN33UCa0xDrUUUUj
250-STARTTLS
250-ID
250 8BITMIME
AUTH LOGIN
334 dXNlcm5hbWU6
MTg2MTAzNzU5xxMzBAMTYzNvbQ==
334 UGFzc3dvcmQ6
TVRSbnlKUVxxk3OEZYUXWg==
235 Authentication successful
```

### 测试邮件报错：`certificate verify failed`

内网邮件服务器若使用自签名证书，可临时放宽校验（生产环境建议换用有效证书）：

```ruby
gitlab_rails['smtp_openssl_verify_mode'] = 'none'
```

修改后重新执行 `gitlab-ctl reconfigure`。

### Rails 控制台无报错，但收不到邮件

1. 查看 Sidekiq 邮件队列日志：

   ```bash
   sudo gitlab-ctl tail sidekiq
   ```

2. 查看邮件相关日志：

   ```bash
   sudo gitlab-ctl tail gitlab-rails
   ```

3. 检查垃圾邮件文件夹
4. 确认 `gitlab_email_from` 与 SMTP 认证邮箱一致或已被服务商允许代发

### 修改配置后未生效

每次修改 `gitlab.rb` 后都必须执行：

```bash
sudo gitlab-ctl reconfigure
```

仅 `gitlab-ctl restart` 不足以加载新的 SMTP 配置。

### 邮件能发出，但显示「发件人未验证」

- 企业邮箱：在 DNS 配置 SPF、DKIM 记录
- 个人邮箱：尽量让 `gitlab_email_from` 与 `smtp_user_name` 保持一致

### SMTP 配置成功，但是用户忘记密码希望重置密码时就是不能收到邮件
* 检查 `gitlab_rails['gitlab_email_from'] = 'GitLab <gitlab@company.com>'` 的格式，如果这种格式可以去掉 `GitLab <>` 试试
* 测试
```bash
$ sudo gitlab-rails console
--------------------------------------------------------------------------------
 Ruby:         ruby 3.3.11 (2026-03-26 revision 1f2d15125a) [x86_64-linux]
 GitLab:       19.1.1 (04cd8ad1a9c) FOSS
 GitLab Shell: 14.54.0
 PostgreSQL:   17.8
------------------------------------------------------------[ booted in 43.25s ]
Loading production environment (Rails 7.2.3.1)
gitlab(prod)> user = User.find_by_email("qf_han@126.com")
=> #<User id:13 @qf_han>
gitlab(prod)> user.state
=> "active"
gitlab(prod)> token = user.send_reset_password_instructions # 此时会发送邮件
=> "VaZz3cudMvPz6xdeWKR8"
gitlab(prod)> mail = DeviseMailer.reset_password_instructions(user, token)
=> 
#<Mail::Message:1038780, Multipart: true, Headers: <From: GitLab <1861345678@163.com>>, <Reply-To: noreply@your-domain.com>, <To: qf_han@126.com>, <Subject: Reset password instruct...
gitlab(prod)> puts mail.from.inspect
gitlab(prod)> puts mail.reply_to.inspect
gitlab(prod)> puts mail.to.inspect
gitlab(prod)> puts mail.subject
["1861345678@163.com"]
["noreply@your-domain.com"]
["qf_han@126.com"]
Reset password instructions
=> nil

```

## 与迁移工具的关系

本仓库的 [用户迁移](../README.md#用户迁移) 会在新实例创建本地用户。邮件配置是可选但强烈推荐的步骤：

| 已配置邮件 | 未配置邮件 |
|------------|------------|
| 用户收到重置密码邮件，可自行设密 | 需管理员在后台手动重置密码 |
| 成员同步后可收到项目通知 | 通知功能不可用 |

建议在完成 [GitLab 安装](gitlab-install-rpm.md)（RPM）或 [Debian/Ubuntu 安装](gitlab-install-deb.md) 后、执行 `gitlab-migrate-users.sh 2` 之前完成邮件配置。

## 参考链接

- [GitLab 官方：SMTP 配置](https://docs.gitlab.com/omnibus/settings/smtp/)

