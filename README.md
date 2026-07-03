# GitLab 迁移工具

本仓库脚本面向 **GitLab 跨多个大版本升级** 场景：当旧实例版本过旧（如 8.x / 9.x），无法直接原地升级到目标版本时，通过「导出仓库 + 用户/成员同步 + 推送到新实例」完成迁移。支持 **Group 项目**与**个人项目**区分迁移、分步执行、断点续传和并行推送。

若你的实例只是 **相近版本的原地升级**（例如 18.x → 19.x），通常无需使用本工具，可直接参考 GitLab 官方升级文档：[Upgrade GitLab](https://docs.gitlab.com/19.1/update/)。

### 为什么跨多个大版本时建议用本工具？

GitLab [官方升级路径](https://docs.gitlab.com/19.1/update/)要求按版本逐级升级，**不能从很旧的版本一步跳到最新版**。例如从 9.x 升到 19.x，往往需要在中间多个大/小版本上反复执行 `gitlab-ctl upgrade`，每一步都伴随数据库迁移、服务重启与回滚风险，整体耗时长、对旧服务器环境（操作系统、PostgreSQL 等）要求也更高。此外，备份恢复通常也受版本约束，难以直接把旧版备份导入全新实例。

相比之下，**「新装 GitLab + 迁移数据」** 是更可控的路径：在新机器上安装目标版本，再把代码仓库与用户权限迁过去，旧实例可继续运行直至切换完成。本工具即针对这一路径做了自动化封装，相比手工逐个 clone/push，主要优势在于：

| 痛点 | 本工具的应对 |
|------|-------------|
| 旧实例 API 已淘汰（v3 在 11.0 移除） | 内置 **v3 → v4** 双 API 适配，可对接 8.x～9.x 等旧实例 |
| 仓库数量多、手工操作易出错 | 批量拉取项目列表，**并行 mirror clone / push** |
| Group 与个人项目结构不同 | 区分 `namespace_kind`，Group 建组、个人项目挂用户命名空间 |
| 迁移后需恢复访问权限 | 独立用户迁移流程：收集用户 → 创建账号 → 同步成员 |
| 中途失败难以续跑 | **分步执行**，已完成的 Group / Project / 本地 mirror 自动跳过 |
| 切换窗口需可控 | 旧实例保持可用，可按项目分批迁移后再统一切流量 |

**迁移范围说明**：本工具聚焦 **Git 仓库数据**（分支、标签、提交历史）及 **用户 / 成员权限**。Issue、Merge Request、Wiki、CI/CD 流水线历史、Package Registry 等 GitLab 元数据**不在迁移范围内**。若你的核心诉求是「把代码从跑不动的旧版本迁到现代实例」，而非完整保留所有协作记录，这种方式通常比逐级原地升级更简单、风险更低。

> **API 版本支持范围**：本工具仅支持以下两种迁移组合，请在 `scripts/config.sh` 中按实例实际 API 配置：
>
> | 场景 | `OLD_GITLAB_API_VERSION` | `NEW_GITLAB_API_VERSION` |
> |------|--------------------------|--------------------------|
> | 旧版 → 新版（常见） | `v3` | `v4` |
> | 现代实例互迁 | `v4` | `v4` |
>
> 目标实例须为 **v4**（`NEW_GITLAB_API_VERSION="v4"`）。不支持 `NEW=v3` 等其它组合。

| GitLab 版本           | API v3 状态                                                                       |
| ------------------- | ------------------------------------------------------------------------------- |
| 8.x                 | v3 为默认 API                                                                      |
| **9.0**             | 引入并推荐使用 **API v4**，v3 仍可使用。([GitLab][1])                                        |
| **9.5**（2017-08-22） | **API v3 停止支持（Unsupported）**，官方建议全部迁移到 v4，但接口仍存在。([GitLab][1])                  |
| **11.0**            | **API v3 被完全删除（Removed）**，访问 `/api/v3/...` 会失败，只能使用 `/api/v4/...`。([GitLab][1]) |

[1]: https://gitlab.com/gitlab-org/gitlab/-/blob/5b0bcf2717b6d47ab87a96d3e7a889ef2225efd1/doc/api/v3_to_v4.md?utm_source=chatgpt.com "doc/api/v3_to_v4.md · 5b0bcf2717b6d47ab87a96d3e7a889ef2225efd1 · GitLab.org / GitLab · GitLab"


## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/hanqunfeng/gitlab-migrate.git
cd gitlab-migrate

# 2. 创建本地配置
cp scripts/config.example.sh scripts/config.sh
# 编辑 scripts/config.sh，填入 OLD_GITLAB / NEW_GITLAB / Token

# 3. 添加执行权限
chmod +x gitlab-migrate.sh gitlab-migrate-users.sh scripts/*.sh

# 4. 仓库迁移（推荐分步执行）
./gitlab-migrate.sh 1    # 拉取项目列表
./gitlab-migrate.sh 2    # 创建 Group（跳过个人 namespace）
./gitlab-migrate.sh 3    # 创建 Project
./gitlab-migrate.sh 4    # Mirror clone
./gitlab-migrate.sh 5    # Push
./gitlab-migrate.sh 6    # 查看汇总

# 5. 用户迁移（独立入口，按需执行）
./gitlab-migrate-users.sh 1    # 收集有项目访问权的用户
./gitlab-migrate-users.sh 2    # 在新实例创建本地用户
./gitlab-migrate-users.sh 3    # 同步 Group / Project 成员
```

> 若源实例含**个人项目**（如 `hanqunfeng/wifitest`），推荐顺序见下文 [含个人项目的推荐流程](#含个人项目的推荐流程)。

## 文档

- [GitLab 安装指南（CE / EE / 极狐）](docs/gitlab-install.md)
- [GitLab 配置 HTTPS 证书指南](docs/gitlab-https-cert.md)
- [GitLab 邮件功能配置指南](docs/gitlab-email-config.md)

## 目录结构

```
.
├── gitlab-migrate.sh          # 仓库迁移入口（步骤 1-6）
├── gitlab-migrate-users.sh    # 用户迁移入口（步骤 1-3，独立）
├── LICENSE
├── .gitignore
├── README.md
├── scripts/
│   ├── common.sh              # 共享工具函数
│   ├── config.example.sh      # 配置模板（提交到仓库）
│   ├── config.sh              # 本地配置（不提交，含 Token）
│   ├── step-01-fetch-projects.sh
│   ├── step-02-create-groups.sh
│   ├── step-03-create-projects.sh
│   ├── step-04-mirror-clone.sh
│   ├── step-05-push.sh
│   ├── step-06-summary.sh
│   ├── user-step-01-fetch-users.sh
│   ├── user-step-02-create-users.sh
│   └── user-step-03-sync-members.sh
└── gitlab-migration/          # 运行时工作目录（自动创建，不提交）
    ├── repos.txt              # 项目列表（步骤 1 生成）
    ├── groups_created.txt     # 新创建的 Group 记录
    ├── projects_created.txt   # 新创建的 Project 记录
    ├── projects_skipped_user.txt  # 因用户未创建而跳过的个人项目
    ├── users.txt              # 待迁移用户（用户步骤 1）
    ├── users_mapped.txt       # 用户 ID 映射（用户步骤 2）
    ├── users_created.txt      # 本次新创建的用户名
    ├── members_fail.log       # 成员同步失败记录
    ├── success.log            # push 成功记录
    ├── fail.log               # push 失败记录
    └── {namespace}/{project}.git/  # mirror 裸仓库
```

## 环境要求

- bash 4+
- `curl`
- `jq`
- `git`

## 配置

首次使用从模板创建本地配置：

```bash
cp scripts/config.example.sh scripts/config.sh
```

编辑 `scripts/config.sh`：

| 变量 | 说明 |
|------|------|
| `OLD_GITLAB` | 源 GitLab 地址 |
| `NEW_GITLAB` | 目标 GitLab 地址 |
| `OLD_TOKEN` | 源实例 PAT，需 `read_repository` 或 `api` 权限 |
| `NEW_TOKEN` | 目标实例 PAT，需 `api` + `write_repository` 权限 |
| `CONCURRENCY` | 步骤 5 并行 push 数量，默认 `6` |
| `OLD_GITLAB_API_VERSION` | 源实例 API 版本，见下表，默认 `v3` |
| `NEW_GITLAB_API_VERSION` | 目标实例 API 版本，**固定填 `v4`**，默认 `v4` |

### API 版本配置（重要）

脚本**仅支持**以下两种组合，须与各实例实际开放的 API 版本一致：

| 迁移场景 | `OLD_GITLAB_API_VERSION` | `NEW_GITLAB_API_VERSION` | 说明 |
|----------|--------------------------|--------------------------|------|
| 旧版 GitLab → 新版 GitLab | `v3` | `v4` | 最常见；源为 GitLab 8.x～9.x 等仅开放 v3 API 的实例 |
| 两个现代实例互迁 | `v4` | `v4` | 源、目标均为 GitLab 9.0+ 且仅使用 v4 API |

配置示例：

```bash
# 旧版 → 新版（默认推荐）
OLD_GITLAB_API_VERSION="v3"
NEW_GITLAB_API_VERSION="v4"

# 两个现代实例
OLD_GITLAB_API_VERSION="v4"
NEW_GITLAB_API_VERSION="v4"
```

**不支持**的配置（请勿使用）：

- `NEW_GITLAB_API_VERSION="v3"` — 目标实例写入逻辑依赖 v4 API（如 `/namespaces`、用户创建参数等）
- 版本号与实例实际 API 不符 — 会导致 HTML 重定向、非 JSON 响应等错误

如何判断源实例用 v3 还是 v4：在浏览器或 `curl` 访问 `https://<源地址>/api/v3/version` 与 `/api/v4/version`，能返回 JSON 的版本即为该实例应填写的值。

> **安全提示**: `scripts/config.sh` 已加入 `.gitignore`，不会被 git 跟踪。请勿手动将其提交到公开仓库。

## 仓库迁移流程（步骤 1-6）

```
步骤 1          步骤 2              步骤 3              步骤 4          步骤 5          步骤 6
拉取项目列表 → 创建 Group      → 创建 Project     → Mirror Clone → Push 到新实例 → 输出汇总
   API         (仅 group)          (group/user)        git            git
```

| 步骤 | 脚本 | 说明 |
|------|------|------|
| 1 | `step-01-fetch-projects.sh` | 分页调用 API，生成 `repos.txt`（含 namespace 类型） |
| 2 | `step-02-create-groups.sh` | 仅为 `group` 命名空间创建 Group；`user` 跳过 |
| 3 | `step-03-create-projects.sh` | Group 项目建在 Group 下；个人项目建在用户命名空间下 |
| 4 | `step-04-mirror-clone.sh` | 从旧 GitLab mirror clone 到本地 |
| 5 | `step-05-push.sh` | 并行 mirror push 到新 GitLab |
| 6 | `step-06-summary.sh` | 统计成功/失败数量 |

### repos.txt 格式

每行一条记录，字段以 `|` 分隔：

```
namespace_kind|namespace|project|http_url_to_repo
```

| 字段 | 说明 |
|------|------|
| `namespace_kind` | `group`（Group 下项目）或 `user`（个人项目） |
| `namespace` | Group 路径或用户名 |
| `project` | 项目名 |
| `http_url_to_repo` | HTTP 克隆地址 |

示例：

```
group|android|nqms|https://gitlab.example.com/android/nqms.git
group|ios|vault-ios|https://gitlab.example.com/ios/vault-ios.git
user|hanqunfeng|wifitest|https://gitlab.example.com/hanqunfeng/wifitest.git
```

### Group 项目 vs 个人项目

GitLab 中 **username 与 Group 的顶级 path 不能重名**。个人项目（如 `hanqunfeng/wifitest`）的 namespace 是用户，**不应**为其创建 Group。

| 类型 | 步骤 2 | 步骤 3 创建位置 |
|------|--------|----------------|
| `group\|ios\|vault-ios` | 创建 Group `ios` | Group `ios` 下 |
| `user\|hanqunfeng\|wifitest` | 跳过 | 用户 `hanqunfeng` 的个人命名空间下 |

个人项目要求目标实例上**已存在对应用户**。若用户尚未创建，步骤 3 会跳过并写入 `projects_skipped_user.txt`；创建用户后重新执行 `./gitlab-migrate.sh 3` 即可。

### 含个人项目的推荐流程

```bash
./gitlab-migrate.sh 1              # 拉列表（识别 group/user）
./gitlab-migrate.sh 2              # 建 Group（自动跳过个人 namespace）

./gitlab-migrate-users.sh 1        # 收集用户
./gitlab-migrate-users.sh 2        # 在新实例创建用户（须在步骤 3 之前）

./gitlab-migrate.sh 3              # 建 Project（个人项目此时可正确创建）
./gitlab-migrate.sh 4 5 6          # clone / push / 汇总

./gitlab-migrate-users.sh 3        # 同步成员关系
```

若仅迁移 Group 项目、不涉及个人项目，可省略用户迁移，或按 `1 → 2 → 3 → 4 → 5 → 6` 顺序执行。

## 用户迁移流程（独立入口）

用户迁移与仓库迁移**分离**，通过 `gitlab-migrate-users.sh` 调度，不修改 `gitlab-migrate.sh` 步骤编号。

```
用户步骤 1           用户步骤 2              用户步骤 3
收集项目访问用户  →  在新实例创建本地用户  →  同步 Group/Project 成员
```

| 步骤 | 脚本 | 说明 |
|------|------|------|
| 1 | `user-step-01-fetch-users.sh` | 从旧实例收集有项目访问权的用户（依赖 `repos.txt`） |
| 2 | `user-step-02-create-users.sh` | 批量创建本地用户；已存在则建立 ID 映射 |
| 3 | `user-step-03-sync-members.sh` | 同步 Group 与 Project 成员到目标实例 |

```bash
./gitlab-migrate-users.sh all      # 执行全部用户迁移步骤
./gitlab-migrate-users.sh 1 2 3     # 分步执行
```

**收集范围**：仅迁移在 `repos.txt` 所列项目上有访问权的用户（含 Group 继承成员与个人项目 owner）。自动跳过 bot 和非 `active` 用户。

**权限要求**：`OLD_TOKEN` / `NEW_TOKEN` 均需管理员 `api` 权限（读取用户邮箱、创建用户、管理成员）。

**输出文件**：

| 文件 | 格式 / 说明 |
|------|-------------|
| `users.txt` | `old_id\|username\|email\|name\|state` |
| `users_mapped.txt` | `old_id\|new_id\|username\|email` |
| `users_created.txt` | 本次新创建的用户名 |
| `members_fail.log` | 成员同步失败记录 |

新用户创建时设 `reset_password=true`，由 GitLab 发送密码重置邮件。用户需自行在新实例重新添加 SSH Key 和 PAT。

## 使用方法

### 仓库迁移

```bash
./gitlab-migrate.sh              # 查看帮助
./gitlab-migrate.sh all          # 执行全部步骤 1-6
./gitlab-migrate.sh 1 2 3        # 组合执行
```

### 用户迁移

```bash
./gitlab-migrate-users.sh        # 查看帮助
./gitlab-migrate-users.sh all    # 执行全部用户步骤 1-3
```

### 直接运行单步脚本

```bash
./scripts/step-04-mirror-clone.sh
./scripts/user-step-01-fetch-users.sh
```

## 认证说明

Git 操作（clone / push）通过 Personal Access Token 认证，无需手动输入用户名密码：

- **用户名**: `oauth2`（GitLab PAT 惯例占位符，非真实用户名）
- **密码**: 对应的 `OLD_TOKEN` 或 `NEW_TOKEN`

手动测试 clone 示例：

```bash
OLD_TOKEN="your_old_token"
repo="https://gitlab.example.com/group/project.git"

git -c "credential.helper=!f() { echo \"username=oauth2\"; echo \"password=${OLD_TOKEN}\"; }; f" \
  clone --mirror "$repo" /tmp/project-test.git
```

API 调用项目路径时，`group/project` 中的斜杠须 URL 编码为 `%2F`：

```bash
project="ios/vault-ios"
encoded=$(jq -nr --arg v "$project" '$v|@uri')
curl -s --header "PRIVATE-TOKEN: $OLD_TOKEN" \
  "$OLD_GITLAB/api/v3/projects/${encoded}"
```

## 断点续传

各步骤均支持重复执行：

| 步骤 | 跳过条件 |
|------|----------|
| 2 | Group 已存在；`user` namespace 始终跳过 |
| 3 | Project 已存在（按 `namespace/project` 路径判断） |
| 4 | 本地 `{namespace}/{project}.git/` 目录已存在 |
| 5 | 无自动跳过，失败项记录在 `fail.log`，可单独重试 |
| 用户 2 | 用户已存在（按 username / email 匹配） |
| 用户 3 | 成员已存在且权限足够则跳过，否则尝试提升 |

步骤 1 每次执行会**清空并重新生成** `repos.txt`。

## 纠错与清理

本工具**不提供**远程删除脚本。新版 GitLab 普遍启用**延迟删除**（保留期至少 1 天，且通常不可关闭），通过 API 删除 Group / Project 只会进入计划删除状态，难以即时回滚，自动化清理价值有限。

**建议做法**：

| 场景 | 处理方式 |
|------|----------|
| 误创建 Group / Project | 在新 GitLab **Web 界面**或 **Admin** 中删除，等待保留期结束 |
| 查看本次新建了哪些资源 | 查看 `gitlab-migration/groups_created.txt`、`projects_created.txt` |
| 清理本地 mirror | 手动删除 `gitlab-migration/{namespace}/{project}.git/` |
| 误将个人 namespace 建成 Group | 在 Admin 删除该 Group，确认步骤 2 已跳过 `user` namespace 后重新迁移 |

迁移前建议在测试环境验证步骤 1–3，确认 `repos.txt` 中 `namespace_kind` 正确后再批量创建资源。

## 日志说明

| 前缀 | 含义 |
|------|------|
| `[INFO]` | 流程信息 |
| `[GROUP]` / `[PROJECT]` / `[USER]` | 正在处理的资源 |
| `[CREATED]` | 新创建成功 |
| `[SKIP]` | 已存在或不需要处理，跳过 |
| `[WARN]` | 警告（如个人项目 members 为空、用户未创建等） |
| `[CLONE]` / `[PUSH]` | Git 操作 |
| `[OK]` / `[FAIL]` | Push 结果（写入 log 文件） |
| `[ERROR]` | 错误 |

## 常见问题

### clone / push 提示输入密码

检查 `OLD_TOKEN` / `NEW_TOKEN` 是否有效，以及是否具备 `read_repository` / `write_repository` 权限。

### 提示未找到 scripts/config.sh

执行 `cp scripts/config.example.sh scripts/config.sh` 并填入你的配置。

### API 返回 HTML 重定向（`You are being redirected`）

常见原因：

1. 项目路径未 URL 编码（`group/project` 须编码为 `group%2Fproject`）
2. API 版本与实例不匹配 — 仅支持 **v3→v4** 或 **v4→v4**，见上文 [API 版本配置](#api-版本配置重要)
3. 将 `OLD_GITLAB_API_VERSION` 配成 `v4`，但源实例实际只有 v3（或反之）

### 旧版 GitLab（v3）拉取成员为空

- `/projects/:id/members` 仅返回**直接成员**，Group 继承成员须通过 `/groups/:id/members` 获取
- 个人项目 `members` 常为 `[]`，权限在 **owner** 上，脚本会自动收集 owner
- v3 的 `namespace` 无 `kind` 字段，步骤 1 通过 `owner_id` 推断类型

### 创建用户报 username 已被使用，但用户列表中找不到

GitLab 的 username 与 Group 顶级 path 共享命名空间。若之前误将个人 namespace 建成了 Group（如 Group `hanqunfeng`），则无法创建同名用户。在 Admin 中删除误建的 Group（等待延迟删除保留期），并确保步骤 2 已正确跳过 `user` namespace 后重试。

### 个人项目步骤 3 被跳过

目标实例上尚无对应用户。先执行 `./gitlab-migrate-users.sh 2` 创建用户，再重新执行 `./gitlab-migrate.sh 3`。跳过记录见 `projects_skipped_user.txt`。

## License

[MIT](LICENSE)
