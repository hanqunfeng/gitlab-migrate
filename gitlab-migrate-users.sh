#!/usr/bin/env bash
#
# GitLab 用户迁移 — 独立入口
#
# 在新实例通过 API 批量创建本地用户，并同步项目/Group 成员关系。
# 仅迁移在 repos.txt 所列项目上有访问权的用户（含 Group 继承成员）。
#
# 前置条件:
#   1. 已配置 scripts/config.sh（与仓库迁移共用）
#   2. 已执行 ./gitlab-migrate.sh 1，生成 gitlab-migration/repos.txt
#   3. 目标实例已创建对应 Group/Project（建议先执行 ./gitlab-migrate.sh 2 3）
#   4. OLD_TOKEN / NEW_TOKEN 均需管理员权限（api）
#
# 用法:
#   ./gitlab-migrate-users.sh all       # 执行全部用户迁移步骤 (1-3)
#   ./gitlab-migrate-users.sh 1 2 3     # 执行指定步骤
#   ./gitlab-migrate-users.sh --help    # 显示帮助
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

usage() {
  cat <<EOF
Usage: $(basename "$0") [all|1|2|3] ...

GitLab 用户迁移 — 独立于仓库迁移流程 (gitlab-migrate.sh)。

步骤说明:
  1  从旧实例收集「有项目访问权」的用户列表（依赖 repos.txt）
  2  在新实例批量创建本地用户（已存在则映射，跳过 bot/非 active）
  3  同步 Group 与 Project 成员关系到新实例

前置条件:
  - scripts/config.sh 已配置 OLD_GITLAB / NEW_GITLAB / Token
  - 旧实例 API 版本: OLD_GITLAB_API_VERSION（默认 v3）
  - 新实例 API 版本: NEW_GITLAB_API_VERSION（默认 v4）
  - 已执行 ./gitlab-migrate.sh 1 生成 repos.txt
  - 建议已执行 ./gitlab-migrate.sh 2 3 创建目标 Group/Project
  - OLD_TOKEN / NEW_TOKEN 需管理员 api 权限

输出文件（位于 gitlab-migration/）:
  users.txt          待迁移用户（old_id|username|email|name|state）
  users_mapped.txt   用户 ID 映射（old_id|new_id|username|email）
  users_created.txt  本次新创建的用户名
  members_fail.log   成员同步失败记录

示例:
  $(basename "$0") all       # 执行全部步骤
  $(basename "$0") 1         # 仅收集用户列表
  $(basename "$0") 2 3       # 创建用户并同步成员

仓库迁移请使用:
  ./gitlab-migrate.sh [all|1|2|3|4|5|6]
EOF
}

run_step() {
  local step=$1
  local script=""

  case "$step" in
    1) script="user-step-01-fetch-users.sh" ;;
    2) script="user-step-02-create-users.sh" ;;
    3) script="user-step-03-sync-members.sh" ;;
    *)
      echo "[ERROR] 未知步骤: $step"
      usage
      exit 1
      ;;
  esac

  echo ""
  echo "========================================"
  echo " 开始执行用户迁移步骤 $step"
  echo "========================================"
  bash "$SCRIPTS_DIR/$script"
}

main() {
  local steps=()

  if [ $# -eq 0 ]; then
    usage
    exit 0
  fi

  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        usage
        exit 0
        ;;
      all)
        steps=(1 2 3)
        ;;
      [1-3])
        steps+=("$arg")
        ;;
      *)
        echo "[ERROR] 未知参数: $arg"
        usage
        exit 1
        ;;
    esac
  done

  for step in "${steps[@]}"; do
    run_step "$step"
  done
}

main "$@"
