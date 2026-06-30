# GitLab 迁移工具

将旧 GitLab 实例上的所有仓库批量迁移到新 GitLab 实例。支持分步执行、断点续传和并行推送。

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/hanqunfeng/gitlab-migrate.git
cd gitlab-migrate

# 2. 创建本地配置
cp scripts/config.example.sh scripts/config.sh
# 编辑 scripts/config.sh，填入 OLD_GITLAB / NEW_GITLAB / Token

# 3. 添加执行权限
chmod +x gitlab-migrate.sh scripts/*.sh

# 4. 分步执行（推荐首次使用）
./gitlab-migrate.sh 1    # 拉取项目列表
./gitlab-migrate.sh 2    # 创建 Group
./gitlab-migrate.sh 3    # 创建 Project
./gitlab-migrate.sh 4    # Mirror clone
./gitlab-migrate.sh 5    # Push
./gitlab-migrate.sh 6    # 查看汇总

# 或一次性执行完整迁移
./gitlab-migrate.sh all
```

## 目录结构

```
.
├── gitlab-migrate.sh          # 统一入口，按参数调度各步骤
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
│   └── step-06-summary.sh
└── gitlab-migration/          # 运行时工作目录（自动创建，不提交）
    ├── repos.txt              # 项目列表（步骤 1 生成）
    ├── groups_created.txt     # 新创建的 group 记录
    ├── projects_created.txt   # 新创建的 project 记录
    ├── success.log            # push 成功记录
    ├── fail.log               # push 失败记录
    └── {group}/{project}.git/ # mirror 裸仓库
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

> **安全提示**: `scripts/config.sh` 已加入 `.gitignore`，不会被 git 跟踪。请勿手动将其提交到公开仓库。

## 迁移流程

```
步骤 1          步骤 2          步骤 3          步骤 4          步骤 5          步骤 6
拉取项目列表 → 创建 Group  → 创建 Project → Mirror Clone → Push 到新实例 → 输出汇总
   API            API            API           git            git
```

| 步骤 | 脚本 | 说明 |
|------|------|------|
| 1 | `step-01-fetch-projects.sh` | 分页调用 API，生成 `repos.txt` |
| 2 | `step-02-create-groups.sh` | 在新 GitLab 创建所需 Group（已存在则跳过） |
| 3 | `step-03-create-projects.sh` | 在对应 Group 下创建 Project（按路径精确判断） |
| 4 | `step-04-mirror-clone.sh` | 从旧 GitLab mirror clone 到本地 |
| 5 | `step-05-push.sh` | 并行 mirror push 到新 GitLab |
| 6 | `step-06-summary.sh` | 统计成功/失败数量 |

### repos.txt 格式

每行一条记录，字段以 `|` 分隔：

```
group|project|http_url_to_repo
```

示例：

```
android|nqms|https://gitlab.example.com/android/nqms.git
ios|vault-ios|https://gitlab.example.com/ios/vault-ios.git
```

## 使用方法

```bash
# 查看帮助（不带参数不会执行任何步骤）
./gitlab-migrate.sh

# 执行完整迁移
./gitlab-migrate.sh all

# 分步执行（推荐首次使用时逐步验证）
./gitlab-migrate.sh 1          # 拉取项目列表
./gitlab-migrate.sh 2          # 创建 Group
./gitlab-migrate.sh 3          # 创建 Project
./gitlab-migrate.sh 4          # Mirror clone
./gitlab-migrate.sh 5          # Push
./gitlab-migrate.sh 6          # 查看汇总

# 组合执行
./gitlab-migrate.sh 1 2 3
./gitlab-migrate.sh 4 5 6
```

也可以直接运行单个步骤脚本：

```bash
./scripts/step-04-mirror-clone.sh
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

## 断点续传

各步骤均支持重复执行：

| 步骤 | 跳过条件 |
|------|----------|
| 2 | Group 已存在 |
| 3 | Project 已存在（按 `group/project` 路径判断） |
| 4 | 本地 `{group}/{project}.git/` 目录已存在 |
| 5 | 无自动跳过，失败项记录在 `fail.log`，可单独重试 |

步骤 1 每次执行会**清空并重新生成** `repos.txt`。

## 日志说明

执行过程中会输出带前缀的日志：

| 前缀 | 含义 |
|------|------|
| `[INFO]` | 流程信息 |
| `[GROUP]` / `[PROJECT]` | 正在处理的资源 |
| `[CREATED]` | 新创建成功 |
| `[SKIP]` | 已存在，跳过 |
| `[CLONE]` / `[PUSH]` | Git 操作 |
| `[OK]` / `[FAIL]` | Push 结果（写入 log 文件） |
| `[ERROR]` | 错误 |

## 发布到 GitHub

```bash
# 确认不会提交敏感文件
git status   # 不应出现 scripts/config.sh 和 gitlab-migration/

git init
git add gitlab-migrate.sh scripts/ README.md LICENSE .gitignore
git commit -m "Initial release: GitLab bulk migration toolkit"
git remote add origin https://github.com/hanqunfeng/gitlab-migrate.git
git push -u origin main
```

## 常见问题

### clone / push 提示输入密码

检查 `OLD_TOKEN` / `NEW_TOKEN` 是否有效，以及是否具备 `read_repository` / `write_repository` 权限。

### 提示未找到 scripts/config.sh

执行 `cp scripts/config.example.sh scripts/config.sh` 并填入你的配置。

## License

[MIT](LICENSE)
