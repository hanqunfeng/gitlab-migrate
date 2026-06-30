#!/usr/bin/env bash
#
# 辅助工具: 删除新 GitLab 上的 Group
#
# 用法:
#   util-delete-group.sh <group> [--force] [--permanent]
#   util-delete-group.sh --from-created [--force] [--permanent]
#
# 注意: 删除 Group 会级联删除其下所有 Project，操作不可恢复。
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

usage() {
  cat <<EOF
Usage: $(basename "$0") <group> [--force]
       $(basename "$0") --from-created [--force]

删除新 GitLab 上的 Group（含其下所有项目）。

示例:
  $(basename "$0") android
  $(basename "$0") android --force
  $(basename "$0") android --permanent --force
  $(basename "$0") --from-created
EOF
}

delete_one_group() {
  local group=$1
  local force=$2
  local permanent=$3

  if [[ "$permanent" == "true" ]]; then
    require_force_or_confirm "[WARN] 将立即永久删除 Group（不走延迟删除）及其下所有项目: $group" "$force" || return 1
  else
    require_force_or_confirm "[WARN] 将删除 Group 及其下所有项目: $group（若 GitLab 启用延迟删除，将进入计划删除）" "$force" || return 1
  fi

  local status
  status=$(gitlab_delete_group "$group" "$permanent")

  case "$status" in
    202|204)
      echo "[DELETED] group: $group"
      remove_line_from_file "groups_created.txt" "$group"
      ;;
    404)
      echo "[SKIP] group not found: $group"
      ;;
    *)
      echo "[ERROR] delete failed for $group (HTTP $status)"
      return 1
      ;;
  esac
}

FORCE=false
FROM_CREATED=false
PERMANENT=false
TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
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
  if [[ ! -f groups_created.txt ]]; then
    echo "[ERROR] 未找到 groups_created.txt，请先执行步骤 2"
    exit 1
  fi

  echo "[INFO] 按 groups_created.txt 批量删除 Group..."
  while IFS= read -r group || [[ -n "${group:-}" ]]; do
    [[ -z "${group:-}" ]] && continue
    delete_one_group "$group" "$FORCE" "$PERMANENT" || true
  done < groups_created.txt
  exit 0
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  usage
  exit 1
fi

for group in "${TARGETS[@]}"; do
  delete_one_group "$group" "$FORCE" "$PERMANENT"
done
