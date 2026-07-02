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

# 解析 repos.txt 一行（兼容旧格式 namespace|project|url）
# 调用后设置: REPO_KIND REPO_NAMESPACE REPO_PROJECT REPO_URL
read_repo_fields() {
  local line=$1
  local f1="" f2="" f3="" f4=""

  IFS='|' read -r f1 f2 f3 f4 <<< "$line"

  if [[ "$f1" == "group" || "$f1" == "user" ]] && [[ -n "${f4:-}" ]]; then
    REPO_KIND=$f1
    REPO_NAMESPACE=$f2
    REPO_PROJECT=$f3
    REPO_URL=$f4
  else
    REPO_KIND="group"
    REPO_NAMESPACE=$f1
    REPO_PROJECT=$f2
    REPO_URL=$f3
  fi
}

# 推断 v3 等无 namespace.kind 时的命名空间类型
infer_namespace_kind() {
  local namespace_json=$1
  local kind owner_id

  kind=$(echo "$namespace_json" | jq -r '.kind // empty')
  if [[ -n "$kind" ]]; then
    echo "$kind"
    return 0
  fi

  owner_id=$(echo "$namespace_json" | jq -r '.owner_id // "null"')
  if [[ "$owner_id" == "null" || -z "$owner_id" ]]; then
    echo "group"
  else
    echo "user"
  fi
}

# 从新 GitLab 获取用户个人 namespace_id（用户须已存在）
resolve_user_namespace_id() {
  local username=$1
  local api_ver user_id resp ns_id

  api_ver=$(resolve_api_version new)

  resp=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/${api_ver}/users?username=$(urlencode "$username")")
  user_id=$(echo "$resp" | jq -r 'if type == "array" then .[0].id // empty else .id // empty end')
  [[ -n "$user_id" ]] || return 1

  resp=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/${api_ver}/namespaces?search=$(urlencode "$username")")
  ns_id=$(echo "$resp" | jq -r --arg u "$username" '
    if type == "array" then
      ([.[] | select(.path == $u and .kind == "user") | .id] | first // empty)
    else empty end
  ')
  if [[ -n "$ns_id" ]]; then
    echo "$ns_id"
    return 0
  fi

  resp=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/${api_ver}/users/${user_id}")
  ns_id=$(echo "$resp" | jq -r '.namespace_id // empty')
  [[ -n "$ns_id" ]] && echo "$ns_id"
}

# URL 编码，用于 GitLab API 路径参数（如 group/project 中的斜杠）
urlencode() {
  jq -nr --arg v "$1" '$v|@uri'
}

# 解析 GitLab API 版本（old 默认 v3，new 默认 v4）
resolve_api_version() {
  local which=$1
  if [[ "$which" == "old" ]]; then
    echo "${OLD_GITLAB_API_VERSION:-v3}"
  else
    echo "${NEW_GITLAB_API_VERSION:-v4}"
  fi
}

# 带 Token 的 API 请求；若返回 HTML 登录页则报错（常见于路径未编码或 API 版本错误）
gitlab_curl_json() {
  local gitlab_url=$1
  local token=$2
  local api_version=$3
  local api_path=$4
  local resp

  resp=$(curl -s --connect-timeout 10 --max-time 60 \
    --header "PRIVATE-TOKEN: $token" \
    "${gitlab_url}/api/${api_version}${api_path}")

  if [[ "$resp" == \<html* ]] || [[ "$resp" == *"You are being"* ]]; then
    echo "[ERROR] API 返回 HTML 重定向，而非 JSON: ${gitlab_url}/api/${api_version}${api_path}" >&2
    echo "[ERROR] 常见原因: group/project 路径未 URL 编码，或 API 版本与实例不匹配" >&2
    return 1
  fi

  if ! echo "$resp" | jq -e . >/dev/null 2>&1; then
    echo "[ERROR] API 返回非 JSON: ${gitlab_url}/api/${api_version}${api_path}" >&2
    echo "[ERROR] 响应片段: ${resp:0:200}" >&2
    return 1
  fi

  printf '%s' "$resp"
}

# 分页拉取 members 或 members/all，逐条输出成员 JSON（每行一个对象）
gitlab_fetch_members() {
  local gitlab_url=$1
  local token=$2
  local api_version=$3
  local members_path=$4
  local page=1

  while true; do
    local resp count
    resp=$(gitlab_curl_json "$gitlab_url" "$token" "$api_version" "${members_path}?per_page=100&page=${page}") || return 1

    if echo "$resp" | jq -e 'type == "object" and (.message? != null or .error? != null)' >/dev/null 2>&1; then
      echo "[WARN] API 错误: ${members_path} -> $(echo "$resp" | jq -r '.message // .error')" >&2
      return 1
    fi

    count=$(echo "$resp" | jq 'if type == "array" then length else 0 end')
    [[ "$count" -eq 0 ]] && break

    echo "$resp" | jq -c '.[]'

    # 不足一页视为最后一页（旧版 v3 可能忽略 page 参数，避免死循环）
    [[ "$count" -lt 100 ]] && break
    page=$((page + 1))
  done
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
