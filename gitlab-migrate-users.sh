#!/usr/bin/env bash
#
# GitLab 用户/成员迁移 — 独立入口（步骤 1–3）
#
# 本脚本用于把“旧实例中的用户与成员关系”迁移到“新实例”：
# - 收集用户：只收集在 `repos.txt` 所列项目上拥有访问权的用户（含 group 继承成员）
# - 创建用户：在新实例创建本地用户（已存在则建立映射），以便个人项目 namespace 能正确创建
# - 同步成员：把旧实例的 group/project 直接成员写入新实例（必要时提升权限）
#
# 典型使用顺序（含个人项目场景）：
# - ./gitlab-migrate.sh 1 2
# - ./gitlab-migrate-users.sh 1 2        # 先在新实例创建用户（否则个人项目无法创建到用户 namespace）
# - ./gitlab-migrate.sh 3 4 5 6
# - ./gitlab-migrate-users.sh 3          # 最后同步成员关系
#
# 前置条件：
# - 已配置 `scripts/config.sh`（与仓库迁移脚本共用）
# - 已执行 `./gitlab-migrate.sh 1` 生成 `WORKDIR/repos.txt`
# - 建议已执行 `./gitlab-migrate.sh 2 3` 在目标实例创建 group/project（成员同步依赖目标资源存在）
# - `OLD_TOKEN` / `NEW_TOKEN` 建议为管理员权限（至少需要：
#   - 旧实例：读取 users / members（很多场景需要管理员 api 才能读到 email）
#   - 新实例：创建用户、管理成员）
#
# 工作目录产物（默认 `./gitlab-migration`）：
# - users.txt          用户迁移步骤 1 生成：old_id|username|email|name|state
# - users_mapped.txt   用户迁移步骤 2 生成：old_id|new_id|username|email
# - users_created.txt  用户迁移步骤 2 生成：本次新创建的用户名（用于审计/回滚）
# - members_fail.log   用户迁移步骤 3 生成：成员同步失败详情
#
# 用法：
#   ./gitlab-migrate-users.sh all       # 执行全部用户迁移步骤 (1-3)
#   ./gitlab-migrate-users.sh 1 2 3     # 执行指定步骤
#   ./gitlab-migrate-users.sh --help    # 显示帮助
#
# 重跑语义（幂等/断点）：
# - 步骤 1：基于 repos.txt 重新收集用户（会覆盖 users.txt）
# - 步骤 2：已存在用户会跳过并建立映射；可安全重跑（会覆盖 users_mapped.txt/users_created.txt）
# - 步骤 3：成员已存在且权限不低于目标值则跳过；否则尝试提升；可安全重跑
#
# 注意：
# - 新用户创建使用 reset_password=true，用户需在新实例自行重置密码并重新配置 SSH Key / PAT
# - 本脚本会通过 API 修改新实例数据（创建用户、写入成员），建议在测试环境先跑通
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
