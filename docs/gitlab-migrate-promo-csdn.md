
# 【开源工具】GitLab 跨大版本迁移实战：告别逐级升级，一键迁移仓库与用户权限

> **摘要**：当 GitLab 实例版本过旧（如 7.x / 8.x / 9.x），官方要求按版本逐级升级，路径长、风险高。本文介绍我开源的 Shell 工具 `gitlab-migrate`——通过「新装 GitLab + 数据迁移」的方式，自动化完成仓库 mirror 迁移、Group/个人项目区分处理、用户权限同步，支持断点续传与并行推送。

---

## 一、背景：为什么需要这个工具？

公司或团队里跑着一个 **GitLab 7.x / 8.x / 9.x** 的老实例，操作系统老旧、PostgreSQL 版本跟不上，想升到 **GitLab 19.x** 却发现：

1. **官方不支持跨大版本直接升级**，必须按 [Upgrade GitLab](https://docs.gitlab.com/update/) 路径逐级 `gitlab-ctl upgrade`；
2. 每一步都伴随数据库迁移、服务重启，一旦失败回滚成本高；
3. 旧版备份往往也无法直接导入全新实例；
4. 更麻烦的是，**GitLab 11.0 起 API v3 被完全移除**，很多自动化脚本对接老实例时会踩坑。

如果你的核心诉求是 **「把代码仓库迁到一台新机器上的现代 GitLab」**，而不是完整保留 Issue、Merge Request、Wiki、CI 流水线历史等协作元数据，那么 **「新装 + 迁移」** 通常比原地逐级升级更简单、更可控。

基于这个场景，我编写并开源了 **`gitlab-migrate`**：

**项目地址**：https://github.com/hanqunfeng/gitlab-migrate

---

## 二、方案对比：原地升级 vs 新装迁移

| 对比项 | 官方逐级升级 | 本工具（新装 + 迁移） |
|:--------|:-------------|:----------------------|
| 适用场景 | 相近版本（如 18.x → 19.x） | 跨多个大版本（如 9.x → 19.x） |
| 对旧服务器要求 | 高（OS、PG 等须满足中间版本） | 低（旧实例只读，新实例独立部署） |
| 迁移内容 | 全量（含 Issue、MR 等） | Git 仓库 + 用户/成员权限 |
| 切换窗口 | 升级期间服务可能中断 | 旧实例可继续运行，分批迁移后统一切流量 |
| 失败恢复 | 回滚复杂 | 分步执行，已完成项自动跳过 |

> **说明**：若你只是 18.x → 19.x 这类相近版本升级，请直接用官方文档，无需本工具。

---

## 三、工具能做什么？

### 3.1 仓库迁移（6 步）

```
步骤 1          步骤 2              步骤 3              步骤 4          步骤 5          步骤 6
拉取项目列表 → 创建 Group      → 创建 Project     → Mirror Clone → Push 到新实例 → 输出汇总
   API         (仅 group)          (group/user)        git            git
```

| 步骤 | 说明 |
|------|:------|
| 1 | 分页调用 API，生成 `repos.txt`（含 namespace 类型） |
| 2 | 仅为 Group 命名空间创建 Group；个人 namespace 自动跳过 |
| 3 | Group 项目建在 Group 下；个人项目建在用户命名空间下 |
| 4 | 从旧 GitLab `git clone --mirror` 到本地 |
| 5 | 并行 `git push --mirror` 到新 GitLab |
| 6 | 统计成功/失败数量 |

### 3.2 用户迁移（3 步，独立入口）

```
用户步骤 1           用户步骤 2              用户步骤 3
收集项目访问用户  →  在新实例创建本地用户  →  同步 Group/Project 成员
```

用户迁移与仓库迁移 **解耦**，可按需执行，不影响仓库步骤编号。

### 3.3 迁移范围

**包含**：
- Git 仓库数据（分支、标签、完整提交历史）
- 用户账号与 Group / Project 成员权限

**不包含**：
- Issue、Merge Request、Wiki
- CI/CD 流水线历史、Package Registry 等元数据

---

## 四、技术亮点

### 4.1 旧版 API v3 适配

GitLab API 版本演进：

| 版本 | API v3 状态 |
|------|:------------|
| 8.x | v3 为默认 API |
| 9.0 | 引入 v4，v3 仍可用 |
| 9.5 | v3 停止支持 |
| **11.0** | **v3 完全移除** |

本工具内置 **v3 → v4** 双 API 适配，支持以下两种迁移组合：

| 场景 | `OLD_GITLAB_API_VERSION` | `NEW_GITLAB_API_VERSION` |
|:------|--------------------------|--------------------------|
| 旧版 → 新版（常见） | `v3` | `v4` |
| 现代实例互迁 | `v4` | `v4` |

### 4.2 Group 与个人项目自动区分

GitLab 中 **username 与 Group 顶级 path 不能重名**。个人项目（如 `hanqunfeng/wifitest`）的 namespace 是用户，不应为其创建 Group。

工具在步骤 1 拉取项目列表时，会识别 `namespace_kind`：

```
group|android|tool|https://gitlab.example.com/android/tool.git
user|hanqunfeng|wifitest|https://gitlab.example.com/hanqunfeng/wifitest.git
```

步骤 2 只为 `group` 类型创建 Group；`user` 类型自动跳过，在步骤 3 挂到对应用户命名空间下。

### 4.3 断点续传

各步骤支持重复执行，已完成的资源自动跳过：

| 步骤 | 跳过条件 |
|------|:----------|
| 2 | Group 已存在 |
| 3 | Project 已存在 |
| 4 | 本地 mirror 目录已存在 |
| 用户 2 | 用户已存在（按 username / email 匹配） |

中途失败可单独重试，无需从头来过。

### 4.4 并行推送

步骤 5 支持配置 `CONCURRENCY`（默认 6），多仓库并行 mirror push，大幅缩短大批量迁移耗时。

---

## 五、快速上手

### 5.1 环境要求

- bash 4+
- `curl`、`jq`、`git`

### 5.2 安装与配置

```bash
# 克隆仓库
git clone https://github.com/hanqunfeng/gitlab-migrate.git
cd gitlab-migrate

# 创建本地配置
cp scripts/config.example.sh scripts/config.sh
```

编辑 `scripts/config.sh`，填入源/目标 GitLab 地址与 Token：

| 变量 | 说明 |
|------|:------|
| `OLD_GITLAB` | 源 GitLab 地址 |
| `NEW_GITLAB` | 目标 GitLab 地址 |
| `OLD_TOKEN` | 源实例 PAT（`read_repository` 或 `api`） |
| `NEW_TOKEN` | 目标实例 PAT（`api` + `write_repository`） |
| `CONCURRENCY` | 并行 push 数量，默认 `6` |

```bash
# 添加执行权限
chmod +x gitlab-migrate.sh gitlab-migrate-users.sh scripts/*.sh
```

### 5.3 仅迁移 Group 项目

```bash
./gitlab-migrate.sh 1    # 拉取项目列表
./gitlab-migrate.sh 2    # 创建 Group
./gitlab-migrate.sh 3    # 创建 Project
./gitlab-migrate.sh 4    # Mirror clone
./gitlab-migrate.sh 5    # Push
./gitlab-migrate.sh 6    # 查看汇总
```

### 5.4 含个人项目的完整流程

个人项目要求目标实例上 **已存在对应用户**，推荐顺序：

```bash
./gitlab-migrate.sh 1              # 拉列表
./gitlab-migrate.sh 2              # 建 Group（跳过个人 namespace）

./gitlab-migrate-users.sh 1        # 收集用户
./gitlab-migrate-users.sh 2        # 创建用户（须在步骤 3 之前）

./gitlab-migrate.sh 3              # 建 Project
./gitlab-migrate.sh 4 5 6          # clone / push / 汇总

./gitlab-migrate-users.sh 3        # 同步成员关系
```

---

## 六、配套文档

仓库内还附带 GitLab 新实例部署相关文档，方便「新装 + 迁移」一条龙：

- [GitLab 安装指南（RPM 系）](https://github.com/hanqunfeng/gitlab-migrate/blob/main/docs/gitlab-install-rpm.md)
- [GitLab 安装指南（DEB 系）](https://github.com/hanqunfeng/gitlab-migrate/blob/main/docs/gitlab-install-deb.md)
- [HTTPS 证书配置](https://github.com/hanqunfeng/gitlab-migrate/blob/main/docs/gitlab-https-cert.md)
- [邮件功能配置](https://github.com/hanqunfeng/gitlab-migrate/blob/main/docs/gitlab-email-config.md)

---

## 七、总结

`gitlab-migrate` 面向 **GitLab 跨多个大版本迁移** 这一特定场景，用 Shell 脚本把「拉列表 → 建资源 → mirror 迁移 → 同步权限」串成可重复执行、可断点续跑的流水线。相比手工逐个 `git clone --mirror` + `git push --mirror`，以及自己处理 v3 API、Group/个人项目差异，这套工具能显著降低出错率和人力成本。

如果你正面临旧 GitLab 无法升级、又需要把代码迁到现代实例的困境，欢迎试用。

- **GitHub**：https://github.com/hanqunfeng/gitlab-migrate
- **协议**：MIT
- 欢迎 Star、提 Issue、PR

---

**标签**：`GitLab` `DevOps` `代码迁移` `Shell` `开源工具` `API v3` `镜像仓库`
