#!/usr/bin/env bash
#
# GitLab 迁移 — 配置模板
#
# 使用方法:
#   cp scripts/config.example.sh scripts/config.sh
#   # 编辑 scripts/config.sh，填入你的 GitLab 地址和 Token
#
# 注意: scripts/config.sh 已加入 .gitignore，不会被提交到仓库。
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
