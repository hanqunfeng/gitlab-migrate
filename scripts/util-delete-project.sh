#!/usr/bin/env bash
#
# 辅助工具: 删除新 GitLab 上的 Project
#
# 用法:
#   util-delete-project.sh <group/project> [--force] [--local] [--permanent]
#   util-delete-project.sh --from-created [--force] [--local] [--permanent]
#
# --force       跳过确认提示
# --local       同时删除本地 mirror 裸仓库 {group}/{project}.git/
# --permanent   立即永久删除（不走延迟删除/回收站，需 GitLab 支持且通常需管理员权限）
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

usage() {
  cat <<EOF
Usage: $(basename "$0") <group/project> [--force] [--local]
       $(basename "$0") --from-created [--force] [--local]

删除新 GitLab 上的项目。可选同时清理本地 mirror 仓库。

示例:
  $(basename "$0") android/nqms
  $(basename "$0") android/nqms --force --local
  $(basename "$0") android/nqms --permanent --force
  $(basename "$0") --from-created
EOF
}

delete_one_project() {
  local project_path=$1
  local force=$2
  local remove_local=$3
  local permanent=$4

  local group="${project_path%%/*}"
  local project="${project_path#*/}"

  if [[ -z "$group" || -z "$project" || "$group" == "$project_path" ]]; then
    echo "[ERROR] 无效路径: $project_path（应为 group/project）"
    return 1
  fi

  if [[ "$permanent" == "true" ]]; then
    require_force_or_confirm "[WARN] 将立即永久删除项目（不走延迟删除/回收站）: $project_path" "$force" || return 1
  else
    require_force_or_confirm "[WARN] 将删除项目: $project_path（若 GitLab 启用延迟删除，将进入计划删除）" "$force" || return 1
  fi

  local status
  status=$(gitlab_delete_project "$project_path" "$permanent")

  case "$status" in
    202|204)
      echo "[DELETED] project: $project_path"
      remove_line_from_file "projects_created.txt" "$project_path"
      ;;
    404)
      echo "[SKIP] project not found: $project_path"
      ;;
    *)
      echo "[ERROR] delete failed for $project_path (HTTP $status)"
      return 1
      ;;
  esac

  if [[ "$remove_local" == "true" ]]; then
    local dir="$group/$project.git"
    if [[ -d "$dir" ]]; then
      rm -rf "$dir"
      echo "[DELETED] local mirror: $dir"
    else
      echo "[SKIP] local mirror not found: $dir"
    fi
  fi
}

FORCE=false
REMOVE_LOCAL=false
FROM_CREATED=false
PERMANENT=false
TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
      ;;
    --local)
      REMOVE_LOCAL=true
      ;;
    --permanent)
      PERMANENT=true
      ;;
    --from-created)
      FROM_CREATED=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "[ERROR] 未知选项: $1"
      usage
      exit 1
      ;;
    *)
      TARGETS+=("$1")
      ;;
  esac
  shift
done

if [[ "$FROM_CREATED" == "true" ]]; then
  if [[ ! -f projects_created.txt ]]; then
    echo "[ERROR] 未找到 projects_created.txt，请先执行步骤 3"
    exit 1
  fi

  echo "[INFO] 按 projects_created.txt 批量删除项目..."
  while IFS= read -r project_path || [[ -n "${project_path:-}" ]]; do
    [[ -z "${project_path:-}" ]] && continue
    delete_one_project "$project_path" "$FORCE" "$REMOVE_LOCAL" "$PERMANENT" || true
  done < projects_created.txt
  exit 0
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  usage
  exit 1
fi

for project_path in "${TARGETS[@]}"; do
  delete_one_project "$project_path" "$FORCE" "$REMOVE_LOCAL" "$PERMANENT"
done
