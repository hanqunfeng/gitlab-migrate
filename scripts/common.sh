#!/usr/bin/env bash
#
# GitLab 迁移 — 共享工具函数
#
# 所有步骤脚本 source 本文件，并通过 load_config 加载用户配置。
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载 scripts/config.sh；若不存在则提示从 config.example.sh 复制
load_config() {
  local config_file="$SCRIPT_DIR/config.sh"

  if [[ ! -f "$config_file" ]]; then
    echo "[ERROR] 未找到 scripts/config.sh"
    echo ""
    echo "首次使用请执行:"
    echo "  cp scripts/config.example.sh scripts/config.sh"
    echo "  # 编辑 scripts/config.sh，填入 GitLab 地址和 Token"
    exit 1
  fi

  # shellcheck source=config.sh
  source "$config_file"
}

# 创建并进入工作目录；所有步骤的数据文件都写在此目录下
init_workdir() {
  mkdir -p "$PROJECT_ROOT/$WORKDIR"
  cd "$PROJECT_ROOT/$WORKDIR"
}

# repos.txt 最后一行若无换行符，bash 的 while read 会跳过该行。
# 在读取 repos.txt 之前调用，确保每一行都能被正确处理。
fix_repos_txt() {
  local f="repos.txt"
  [[ -s "$f" ]] || return 0
  [[ $(tail -c1 "$f") == $'\n' ]] || echo >> "$f"
}

# URL 编码，用于 GitLab API 路径参数（如 group/project 中的斜杠）
urlencode() {
  jq -nr --arg v "$1" '$v|@uri'
}

# 交互确认；传入 --force 时跳过（便于脚本化调用）
require_force_or_confirm() {
  local message=$1
  local force=${2:-false}

  if [[ "$force" == "true" ]]; then
    return 0
  fi

  echo "$message"
  read -r -p "确认继续? [y/N] " answer
  case "${answer,,}" in
    y|yes) return 0 ;;
    *) echo "[ABORT] 已取消"; return 1 ;;
  esac
}

# 删除新 GitLab 上的项目，返回 HTTP 状态码
gitlab_delete_project() {
  local project_path=$1
  local permanent=${2:-false}

  local url="$NEW_GITLAB/api/v4/projects/$(urlencode "$project_path")"
  if [[ "$permanent" == "true" ]]; then
    url="${url}?permanently_remove=true"
  fi

  curl -s -o /dev/null -w "%{http_code}" \
    --request DELETE \
    --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$url"
}

# 删除新 GitLab 上的 Group（会级联删除其下所有项目），返回 HTTP 状态码
gitlab_delete_group() {
  local group_path=$1
  local permanent=${2:-false}

  local url="$NEW_GITLAB/api/v4/groups/$(urlencode "$group_path")"
  if [[ "$permanent" == "true" ]]; then
    url="${url}?permanently_remove=true"
  fi

  curl -s -o /dev/null -w "%{http_code}" \
    --request DELETE \
    --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$url"
}

# 从记录文件中移除一行（用于删除后同步 groups_created.txt / projects_created.txt）
remove_line_from_file() {
  local file=$1
  local line=$2

  [[ -f "$file" ]] || return 0
  grep -Fxv "$line" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}
