# GitLab API 指南（v3 与 v4 对比）

本文档介绍 GitLab REST API 的 **v3** 与 **v4** 差异，并结合本仓库迁移工具的实际调用场景说明：如何判断版本、常见接口对比、v4 独有能力，以及排障要点。

> 官方背景：GitLab 自 **9.0** 起引入并推荐 **API v4**；**9.5** 起 v3 停止支持；**11.0** 起 v3 被完全移除。现代实例（11.0+）只能使用 v4。

## 版本生命周期

| GitLab 版本 | API v3 | API v4 |
|-------------|--------|--------|
| 8.x | 默认 API | 不可用 |
| 9.0 | 仍可用，但不推荐 | 引入并推荐使用 |
| 9.5（2017-08-22） | **停止支持（Unsupported）** | 推荐使用 |
| 11.0+ | **已删除（Removed）** | 唯一可用 REST API |

## 如何判断实例使用 v3 还是 v4

在浏览器或终端分别探测：

```bash
# 探测 v4
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/version" | jq .

# 探测 v3（仅旧实例可能成功，gitlab 8.13 以后才加入 /version 这个接口）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/version" | jq .
```

能返回 JSON（含 `version` 字段）的路径，即为该实例应使用的 API 版本。

本仓库 `scripts/config.sh` 中：

| 场景 | `OLD_GITLAB_API_VERSION` | `NEW_GITLAB_API_VERSION` |
|------|--------------------------|--------------------------|
| 旧版 → 新版（常见） | `v3` | `v4` |
| 现代实例互迁 | `v4` | `v4` |

**目标实例必须为 v4**（`NEW_GITLAB_API_VERSION="v4"`）。本工具不支持 `NEW=v3`。

## 共同基础

下文示例统一使用以下变量，复制前请替换为你的实际值：

```bash
GITLAB="https://gitlab.example.com"   # GitLab 地址，不要带末尾斜杠
TOKEN="your_personal_access_token"    # PAT 或旧版 Private Token

# 示例路径
GROUP="android"
PROJECT="tool"
PROJECT_PATH="android/tool"              # group 项目
USER_PROJECT_PATH="hanqunfeng/wifitest"  # 个人项目
USERNAME="hanqunfeng"
USER_ID="42"
NAMESPACE_ID="123"

# URL 编码（含斜杠的路径必须编码）
ENCODED_PATH=$(jq -nr --arg v "$PROJECT_PATH" '$v|@uri')
ENCODED_USER_PATH=$(jq -nr --arg v "$USER_PROJECT_PATH" '$v|@uri')
```

### 基础 URL 格式

```
https://<gitlab-host>/api/v3/<endpoint>   # 旧版
https://<gitlab-host>/api/v4/<endpoint>   # 现代
```

### 认证方式（v3 / v4 相同）

新版本使用 `Personal Access Token（PAT）`，老版本使用 `Private Token`，通过请求头传递：

```bash
# v4 认证示例
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects?per_page=10" | jq .

# v3 认证示例（仅旧实例）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/projects?per_page=10" | jq .
```

创建`Personal Access Token（PAT）`时分配的常见权限（迁移相关）, `Private Token` 拥有全部权限：

| 操作 | 建议 scope |
|------|------------|
| 读取项目/用户/成员 | `api` 或 `read_api` |
| 创建 Group/Project/用户 | `api` |
| git clone | `read_repository` |
| git push | `write_repository` |

### 路径编码（v3 / v4 均需注意）

项目路径 `group/subgroup/project` 中的 `/` 必须 URL 编码为 `%2F`：

```bash
# 错误：未编码，可能返回 HTML 重定向
/api/v4/projects/group/subgroup/project

# 正确
/api/v4/projects/group%2Fsubgroup%2Fproject
```

bash 中可用 `jq` 编码：

```bash
ENCODED_PATH=$(jq -nr --arg v "$PROJECT_PATH" '$v|@uri')

curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}" | jq .
```

### 分页（基本相同）

```bash
# v4 示例：第 1 页，每页 100 条
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects?per_page=100&page=1"

# v3 示例（仅旧实例）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/projects?per_page=100&page=1"
```

> v3 部分旧端点可能忽略 `page` 参数或分页行为不一致；本仓库在拉取 members 时会检测“不足一页即停止”，避免死循环。

---

## 迁移相关接口对比

以下按本仓库脚本实际用到的 API 进行对比。

### 1）获取版本信息

| 项目 | v3 | v4 |
|------|----|----|
| 端点 | `GET /api/v3/version` | `GET /api/v4/version` |
| 用途 | 探测 API 是否可用 | 探测 API 是否可用 |

```bash
# v4
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/version" | jq .

# v3（仅旧实例）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/version" | jq .
```

### 2）项目列表

| 项目 | v3 | v4 |
|------|----|----|
| 端点 | `GET /api/v3/projects` | `GET /api/v4/projects` |
| 分页 | `per_page` + `page` | `per_page` + `page` |
| 简化字段 | `simple=true` | `simple=true` |

**namespace 类型识别差异（重要）**：

| 字段 | v3 | v4 |
|------|----|----|
| `namespace.kind` | 通常**不存在** | 存在：`group` / `user` |
| 推断个人项目 | 看 `namespace.owner_id` 是否有值 | 优先用 `namespace.kind == "user"` |

本仓库步骤 1 的逻辑：

```ruby
# 伪代码
if namespace.kind
  kind = namespace.kind
elsif namespace.owner_id == null
  kind = "group"
else
  kind = "user"
end
```

```bash
# v4：拉取项目列表（simple 减少字段体积）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects?per_page=100&page=1&simple=true" | jq .

# v3：拉取项目列表
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/projects?per_page=100&page=1&simple=true" | jq .

# v4：只看 namespace.kind / owner_id（便于区分 group/user 项目）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects?per_page=100&page=1&simple=true" \
  | jq '.[] | {path, namespace: {path: .namespace.path, kind: .namespace.kind, owner_id: .namespace.owner_id}}'
```

### 3）获取单个项目

| 项目 | v3 | v4 |
|------|----|----|
| 端点 | `GET /api/v3/projects/:id_or_encoded_path` | `GET /api/v4/projects/:id_or_encoded_path` |
| 路径编码 | 需要 | 需要 |

v4 返回的 `namespace` 信息更完整（含 `kind`），便于区分 Group 项目与个人项目。

```bash
# v4：按编码路径获取 group 项目
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}" | jq .

# v4：按编码路径获取个人项目
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_USER_PATH}" | jq .

# v4：按 numeric id 获取（id 从列表接口中获得）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/123" | jq .

# v3：按编码路径获取项目
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/projects/${ENCODED_PATH}" | jq .
```

### 4）Group 管理

| 操作 | v3 | v4 |
|------|----|----|
| 搜索 Group | `GET /api/v3/groups?search=<name>` | `GET /api/v4/groups?search=<name>` |
| 获取 Group | `GET /api/v3/groups/:id_or_path` | `GET /api/v4/groups/:id_or_path` |
| 创建 Group | `POST /api/v3/groups` | `POST /api/v4/groups` |

创建参数（本仓库使用）：

```
name=<name>&path=<path>
```

```bash
# v4：搜索 Group
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/groups?search=$GROUP" | jq .

# v4：按 path 获取 Group（并取出 namespace_id）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/groups/$GROUP" | jq '{id, name, path, full_path}'

# v4：创建 Group（本仓库步骤 2 同款）
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "name=$GROUP&path=$GROUP" \
  "$GITLAB/api/v4/groups" | jq .

# v3：搜索 Group
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/groups?search=$GROUP" | jq .

# v3：创建 Group
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "name=$GROUP&path=$GROUP" \
  "$GITLAB/api/v3/groups" | jq .
```

### 5）Project 管理

| 操作 | v3 | v4 |
|------|----|----|
| 检查是否存在 | `GET /api/v3/projects/:encoded_path` | `GET /api/v4/projects/:encoded_path` |
| 创建 Project | `POST /api/v3/projects` | `POST /api/v4/projects` |

创建参数（本仓库使用）：

```
name=<project>&namespace_id=<namespace_id>
```

> v4 通过 `namespace_id` 明确指定项目归属（Group 或用户个人命名空间），是本仓库创建个人项目的关键。

```bash
# v4：检查项目是否存在（200=存在，404=不存在）
curl -s -o /dev/null -w "%{http_code}\n" \
  --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}"

# v4：在 Group 下创建 Project（本仓库步骤 3 同款）
# 1) 获取 Group 的 namespace_id
NAMESPACE_ID=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/groups/$GROUP" | jq -r '.id')

# 2) 创建项目
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "name=$PROJECT&namespace_id=$NAMESPACE_ID" \
  "$GITLAB/api/v4/projects" | jq .

# v4：在用户个人命名空间下创建 Project
USER_NAMESPACE_ID=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/namespaces?search=$USERNAME" \
  | jq -r --arg u "$USERNAME" '[.[] | select(.path == $u and .kind == "user") | .id] | first')

curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "name=wifitest&namespace_id=$USER_NAMESPACE_ID" \
  "$GITLAB/api/v4/projects" | jq .

# v3：检查项目是否存在
curl -s -o /dev/null -w "%{http_code}\n" \
  --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/projects/${ENCODED_PATH}"

# v3：创建 Project
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "name=$PROJECT&namespace_id=$NAMESPACE_ID" \
  "$GITLAB/api/v3/projects" | jq .
```

### 6）用户管理

| 操作 | v3 | v4 |
|------|----|----|
| 按 username 查找 | `GET /api/v3/users?username=<name>` | `GET /api/v4/users?username=<name>` |
| 按 search 查找 | `GET /api/v3/users?search=<q>` | `GET /api/v4/users?search=<q>` |
| 获取用户详情 | `GET /api/v3/users/:id` | `GET /api/v4/users/:id` |
| 创建用户 | `POST /api/v3/users` | `POST /api/v4/users` |

创建用户时本仓库使用的 v4 参数：

```
email=...&username=...&name=...&reset_password=true&skip_confirmation=true
```

| 参数 | v3 | v4 | 说明 |
|------|----|----|------|
| `skip_confirmation` | 可能不支持或行为不同 | 支持 | 跳过邮箱确认，便于批量迁移 |
| `reset_password` | 视版本而定 | 支持 | 发送密码重置邮件 |

```bash
# v4：按 username 查找用户
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/users?username=$USERNAME" | jq .

# v4：按 email 搜索用户
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/users?search=han@example.com" | jq .

# v4：获取用户详情
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/users/$USER_ID" | jq .

# v4：创建用户（本仓库用户步骤 2 同款，需管理员权限）
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "email=han@example.com&username=$USERNAME&name=Han%20Qunfeng&reset_password=true&skip_confirmation=true" \
  "$GITLAB/api/v4/users" | jq .

# v3：按 username 查找用户
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/users?username=$USERNAME" | jq .

# v3：获取用户详情
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/users/$USER_ID" | jq .

# v3：创建用户（参数因旧版本而异，仅供参考）
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "email=han@example.com&username=$USERNAME&name=Han%20Qunfeng&password=TempPass123&confirmed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$GITLAB/api/v3/users" | jq .
```

### 7）成员（Members）——差异最大

| 端点 | v3 | v4 | 返回范围 |
|------|----|----|----------|
| `.../members` | 支持 | 支持 | **仅直接成员** |
| `.../members/all` | **不存在** | **支持** | 直接成员 + 继承成员 |

适用资源：

- Group：`/groups/:id_or_path/members` / `members/all`
- Project：`/projects/:id_or_path/members` / `members/all`

**对本仓库迁移的影响**：

| 场景 | v3 做法 | v4 做法 |
|------|---------|---------|
| Group 继承成员 | 必须单独拉 Group members；项目 members 拿不到继承权限 | 可用 `members/all` 一次拿到继承成员 |
| 个人项目 members 为空 | 正常；权限在 **owner** 上，需从 `project.owner` / `namespace.owner_id` 收集 | 同样可能为空；也可用 owner 信息补充 |

本仓库用户步骤 1 的策略：

- v4：优先尝试 `members/all`，再回退 `members`
- v3：仅使用 `members`，并额外收集 project owner

access_level 常用值：`10=Guest`，`20=Reporter`，`30=Developer`，`40=Maintainer`，`50=Owner`

```bash
# --- Group 成员 ---

# v4：Group 直接成员
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/groups/$GROUP/members?per_page=100&page=1" | jq .

# v4：Group 全部成员（含继承，v4 独有）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/groups/$GROUP/members/all?per_page=100&page=1" | jq .

# v3：Group 成员（无 members/all）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/groups/$GROUP/members?per_page=100&page=1" | jq .

# --- Project 成员 ---

# v4：Project 直接成员
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/members?per_page=100&page=1" | jq .

# v4：Project 全部成员（含 Group 继承，v4 独有）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/members/all?per_page=100&page=1" | jq .

# v3：Project 成员
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v3/projects/${ENCODED_PATH}/members?per_page=100&page=1" | jq .

# --- 添加 / 更新成员（本仓库用户步骤 3 写入目标实例） ---

# v4：向 Group 添加成员
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "user_id=$USER_ID&access_level=30" \
  "$GITLAB/api/v4/groups/$GROUP/members" | jq .

# v4：向 Project 添加成员
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "user_id=$USER_ID&access_level=40" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/members" | jq .

# v4：提升已有成员权限
curl -s --request PUT \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "access_level=40" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/members/$USER_ID" | jq .
```

### 8）Namespaces（v4 独有，迁移关键）

| 项目 | v3 | v4 |
|------|----|----|
| 端点 | **无独立 Namespaces API** | `GET /api/v4/namespaces` |
| 搜索 | — | `?search=<username>` |
| 返回 `kind` | — | `group` / `user` |

本仓库用 v4 `/namespaces` 解析用户个人 `namespace_id`，以便在个人命名空间下创建项目：

```bash
# v4：搜索用户个人命名空间（本仓库步骤 3 同款）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/namespaces?search=$USERNAME" \
  | jq --arg u "$USERNAME" '[.[] | select(.path == $u and .kind == "user")]'

# v4：回退方案——从用户详情获取 namespace_id
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/users?username=$USERNAME" \
  | jq '.[0] | {id, username, namespace_id}'
```

回退方案：`GET /api/v4/users/:id` 读取 `namespace_id` 字段。

---

## v4 独有能力概览

除上述迁移相关差异外，v4 相对 v3 还引入/完善了大量能力。以下按类别列举，并给出 **v4 完整 curl 示例**（v3 均不可用或极不完整）。

### REST API 设计与一致性

- 更规范的 REST 资源命名与 HTTP 动词
- 更统一的错误响应格式（`message` / `error` 字段）
- 更完善的分页头（`X-Total`、`X-Total-Pages`、`X-Page` 等，视端点而定）
- 支持用 **numeric id** 或 **URL 编码 path** 访问多数资源

```bash
# 查看分页响应头
curl -s -D - -o /dev/null \
  --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects?per_page=10&page=1" \
  | grep -i '^X-'
```

### 成员与权限

- `members/all`：获取继承成员（见上文 [7）成员](#7成员members差异最大)）
- 更细粒度的 access level 与过期时间 `expires_at`
- 群组/项目级别的更完整权限 API

```bash
# 添加带过期时间的成员
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "user_id=$USER_ID&access_level=30&expires_at=2026-12-31" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/members" | jq .
```

### 命名空间与组织结构

- `/namespaces` API：统一查询 Group 与用户命名空间（见上文 [8）Namespaces](#8namespacesv4-独有迁移关键)）
- `namespace.kind` 字段：明确区分 `group` / `user`
- 更完善的 Subgroup、共享 Group 等管理能力

```bash
# 列出可访问的 namespaces
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/namespaces?per_page=100&page=1" | jq .

# 创建 Subgroup
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "name=mobile&path=mobile&parent_id=12" \
  "$GITLAB/api/v4/groups" | jq .
```

### CI/CD 与 DevOps

- Pipeline / Job / Artifact / Runner 等现代 CI API
- 环境（Environments）、部署（Deployments）
- 容器镜像仓库（Container Registry）API
- Package Registry（Maven/NuGet 等）API

```bash
# 列出项目 Pipeline
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/pipelines?per_page=20" | jq .

# 获取 Pipeline 的 Jobs
PIPELINE_ID=100
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/pipelines/${PIPELINE_ID}/jobs" | jq .

# 列出项目 Runners
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/runners" | jq .
```

### 安全与合规

- 依赖项扫描（Dependency Scanning）
- 容器扫描（Container Scanning）
- SAST / DAST API
- 漏洞报告（Vulnerability Findings）

```bash
# 列出项目漏洞（需相应功能与权限）
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/vulnerabilities?per_page=20" | jq .
```

### 集成与自动化

- Webhook 管理更完善
- Deploy Tokens / Deploy Keys
- Project Access Tokens / Group Access Tokens
- 更完整的 Integrations API

```bash
# 列出项目 Webhooks
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/hooks" | jq .

# 创建项目 Webhook
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"url":"https://example.com/hook","push_events":true,"merge_requests_events":true}' \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/hooks" | jq .

# 列出 Deploy Keys
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/deploy_keys" | jq .

# 创建 Project Access Token
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"name":"ci-token","scopes":["read_repository","read_api"],"expires_at":"2026-12-31"}' \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/access_tokens" | jq .
```

### 其他现代能力

- **GraphQL API**（`/api/graphql`）：v4 时代主推的查询方式，适合复杂聚合查询
- Issue/MR 高级操作（时间跟踪、评审规则、审批规则等）
- Wiki、Snippets、Milestones、Labels 等资源的完整 CRUD
- 审计事件（Audit Events，EE）
- Geo 复制相关 API（EE）

```bash
# GraphQL：查询当前用户
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"query":"{ currentUser { id username name } }"}' \
  "$GITLAB/api/graphql" | jq .

# 列出项目 Issues
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/issues?per_page=20&state=opened" | jq .

# 列出项目 Merge Requests
curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/merge_requests?per_page=20&state=opened" | jq .

# 创建 Milestone
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --data "title=v1.0&description=First%20release&due_date=2026-12-31" \
  "$GITLAB/api/v4/projects/${ENCODED_PATH}/milestones" | jq .
```

> 完整端点列表以官方文档为准：[GitLab REST API](https://docs.gitlab.com/api/rest/)

---

## 与本仓库迁移工具的对应关系

| 迁移步骤 | 主要 API | 版本要求 |
|----------|----------|----------|
| 步骤 1 拉取项目 | `GET /projects` | 源：v3 或 v4 |
| 步骤 2 创建 Group | `GET/POST /groups` | 目标：v4 |
| 步骤 3 创建 Project | `GET/POST /projects`，`GET /namespaces` | 目标：v4 |
| 用户步骤 1 收集用户 | `GET /groups/*/members`，`GET /projects/*/members`，v4 额外 `members/all` | 源：v3 或 v4 |
| 用户步骤 2 创建用户 | `GET/POST /users` | 目标：v4 |
| 用户步骤 3 同步成员 | `GET /*/members`（源），`POST/PUT /*/members`（目标） | 源：v3 或 v4；目标：v4 |
| 步骤 4/5 Git 操作 | HTTP(S) git + PAT | 与 API 版本无关 |

---

## 常见问题

### API 返回 HTML 重定向（`You are being redirected`）

常见原因：

1. **路径未 URL 编码**（`group/project` 须写成 `group%2Fproject`）
2. **API 版本与实例不匹配**（如对 11.0+ 实例访问 v3）
3. **Token 无效或权限不足**，被重定向到登录页

### v3 拉取成员为空

- `/projects/:id/members` 只返回**直接成员**，不含 Group 继承
- 个人项目 `members` 常为 `[]`，需从 `owner` / `namespace.owner_id` 收集
- v3 无 `members/all`，需单独拉 Group members

### 创建用户报 username 已被使用

GitLab 的 **username 与 Group 顶级 path 共享命名空间**。若误将个人 namespace 建成了 Group（如 Group `hanqunfeng`），则无法创建同名用户。需在 Admin 删除误建 Group 后重试。

### 如何判断该用哪个版本

```bash
curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB/api/v4/version" | jq .   # 有 JSON → v4
curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB/api/v3/version" | jq .   # 有 JSON → v3（仅旧实例）
```

---

## 参考链接

- [GitLab REST API 文档](https://docs.gitlab.com/api/rest/)
- [GitLab API v4 说明文档](https://gitlab.com/gitlab-org/gitlab/-/blob/master/doc/api/_index.md?ref_type=heads)
- [GitLab GraphQL API](https://docs.gitlab.com/api/graphql/)
- [本仓库 README — API 版本配置](../README.md#api-版本配置重要)
