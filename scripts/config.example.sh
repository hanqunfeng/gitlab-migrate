#!/usr/bin/env bash
#
# GitLab 迁移 — 配置模板（复制为 config.sh 后生效）
#
# 本文件是可提交的“示例模板”，实际运行时脚本会加载 `scripts/config.sh`。
# 为避免泄露 token：`scripts/config.sh` 已在 .gitignore 中忽略，请勿手动提交。
#
# 使用方法：
#   cp scripts/config.example.sh scripts/config.sh
#   $EDITOR scripts/config.sh
#
# 约定：
# - OLD_* 用于读取旧实例（API + git clone）
# - NEW_* 用于写入新实例（API 创建资源 + git push）
#
# 权限建议（PAT scopes）：
# - OLD_TOKEN：至少 `read_repository` + `api`（或 `read_api`），用于拉项目列表/成员并进行 clone
# - NEW_TOKEN：至少 `api` + `write_repository`，用于创建 group/project/user 并 push
#
# 注意事项：
# - 若旧实例为 v3 且出现“管理员 token 仍拉不到全量项目”，可考虑在步骤 1 使用 /projects/all
# - 若新实例启用了强制邮箱验证/外部身份源，创建用户可能需要额外配置（见 README/文档）
#

# ---------------------------------------------------------------------------
# GitLab 实例地址
# ---------------------------------------------------------------------------
OLD_GITLAB="https://old-gitlab.example.com"   # 源 GitLab（待迁移）
NEW_GITLAB="https://new-gitlab.example.com" # 目标 GitLab

# ---------------------------------------------------------------------------
# Personal Access Token
# OLD_TOKEN: 需 read_repository / api 权限，用于 API 拉取列表 + git clone
# NEW_TOKEN: 需 api + write_repository 权限，用于 API 创建资源 + git push
# ---------------------------------------------------------------------------
OLD_TOKEN="your_old_token"
NEW_TOKEN="your_new_token"

# ---------------------------------------------------------------------------
# 运行参数
# ---------------------------------------------------------------------------
WORKDIR="./gitlab-migration"  # 工作目录（存放 repos.txt、镜像仓库、日志等）
CONCURRENCY=6                 # 步骤 5 并行 push 的并发数

# ---------------------------------------------------------------------------
# API 版本（按实例分别配置，须与实例实际开放的 API 一致）
#
# 本工具仅支持以下两种组合：
#   1. 旧版 → 新版（常见）: OLD=v3, NEW=v4
#   2. 现代实例互迁:        OLD=v4, NEW=v4
#
# NEW 必须为 v4（目标实例写入依赖 v4 API）。不支持 NEW=v3。
# 判断方法: curl https://<地址>/api/v4/version，能返回 JSON 即说明v4可用。
# 详见 README.md「API 版本配置」。
# ---------------------------------------------------------------------------
OLD_GITLAB_API_VERSION="v3"   # 源实例: v3（旧版）或 v4（现代）
NEW_GITLAB_API_VERSION="v4"   # 目标实例: 固定 v4
