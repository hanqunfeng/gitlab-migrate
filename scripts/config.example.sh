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
