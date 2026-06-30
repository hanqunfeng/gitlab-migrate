#!/usr/bin/env bash
#
# GitLab 迁移工具 — 辅助功能入口
#
# 与核心迁移步骤 (1-6) 分离，用于纠错、清理等操作。
#
# 用法:
#   ./gitlab-util.sh delete-project <group/project> [--force] [--local] [--permanent]
#   ./gitlab-util.sh delete-project --from-created [--force] [--local] [--permanent]
#   ./gitlab-util.sh delete-group <group> [--force] [--permanent]
#   ./gitlab-util.sh delete-group --from-created [--force] [--permanent]
#   ./gitlab-util.sh delete-local <group/project> [--force]
#   ./gitlab-util.sh delete-local --all [--force]
#   ./gitlab-util.sh list-created
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

辅助命令（独立于核心迁移步骤 1-6）:

  delete-project <group/project>   删除新 GitLab 上的项目
    --from-created                 按 projects_created.txt 批量删除
    --force                        跳过确认
    --local                        同时删除本地 mirror 裸仓库
    --permanent                    立即永久删除（不走延迟删除/回收站，需 GitLab 支持且通常需管理员权限）

  delete-group <group>             删除新 GitLab 上的 Group（含其下所有项目）
    --from-created                 按 groups_created.txt 批量删除
    --force                        跳过确认
    --permanent                    立即永久删除（不走延迟删除，需 GitLab 支持且通常需管理员权限）

  delete-local <group/project>     仅删除本地 mirror 裸仓库
    --all                          按 repos.txt 批量删除
    --force                        跳过确认

  list-created                     查看 groups_created.txt / projects_created.txt

核心迁移请使用:
  ./gitlab-migrate.sh [all|1|2|3|4|5|6]

示例:
  $(basename "$0") delete-project android/nqms
  $(basename "$0") delete-group wrong-group --force
  $(basename "$0") delete-project --from-created --local --force
  $(basename "$0") list-created
EOF
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  local command=$1
  shift

  case "$command" in
    -h|--help|help)
      usage
      exit 0
      ;;
    delete-project)
      bash "$SCRIPTS_DIR/util-delete-project.sh" "$@"
      ;;
    delete-group)
      bash "$SCRIPTS_DIR/util-delete-group.sh" "$@"
      ;;
    delete-local)
      bash "$SCRIPTS_DIR/util-delete-local.sh" "$@"
      ;;
    list-created)
      bash "$SCRIPTS_DIR/util-list-created.sh" "$@"
      ;;
    *)
      echo "[ERROR] 未知命令: $command"
      usage
      exit 1
      ;;
  esac
}

main "$@"
