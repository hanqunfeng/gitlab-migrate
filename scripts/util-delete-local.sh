#!/usr/bin/env bash
#
# 辅助工具: 删除本地 mirror 裸仓库
#
# 用法:
#   util-delete-local.sh <group/project> [--force]
#   util-delete-local.sh --all [--force]
#
# 仅删除 WORKDIR 下的 {group}/{project}.git/，不影响 GitLab 远程仓库。
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

usage() {
  cat <<EOF
Usage: $(basename "$0") <group/project> [--force]
       $(basename "$0") --all [--force]

删除本地 mirror 裸仓库，不影响新 GitLab 上的远程项目。

示例:
  $(basename "$0") android/nqms
  $(basename "$0") --all --force
EOF
}

delete_one_local() {
  local project_path=$1
  local force=$2

  local group="${project_path%%/*}"
  local project="${project_path#*/}"

  if [[ -z "$group" || -z "$project" || "$group" == "$project_path" ]]; then
    echo "[ERROR] 无效路径: $project_path（应为 group/project）"
    return 1
  fi

  local dir="$group/$project.git"

  if [[ ! -d "$dir" ]]; then
    echo "[SKIP] local mirror not found: $dir"
    return 0
  fi

  require_force_or_confirm "[WARN] 将删除本地目录: $dir" "$force" || return 1
  rm -rf "$dir"
  echo "[DELETED] local mirror: $dir"
}

FORCE=false
DELETE_ALL=false
TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
      ;;
    --all)
      DELETE_ALL=true
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

if [[ "$DELETE_ALL" == "true" ]]; then
  if [[ ! -f repos.txt ]]; then
    echo "[ERROR] 未找到 repos.txt，请先执行步骤 1"
    exit 1
  fi

  fix_repos_txt
  echo "[INFO] 按 repos.txt 批量删除本地 mirror..."
  while IFS='|' read -r group project _repo || [[ -n "${group:-}" ]]; do
    [[ -z "${group:-}" ]] && continue
    delete_one_local "$group/$project" "$FORCE" || true
  done < repos.txt
  exit 0
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  usage
  exit 1
fi

for project_path in "${TARGETS[@]}"; do
  delete_one_local "$project_path" "$FORCE"
done
