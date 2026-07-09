#!/usr/bin/env bash
#
# GitLab 迁移 — 共享工具函数库（被所有 step 脚本 source）
#
# 本文件集中放置“跨脚本复用”的能力，目标是：
# - 统一配置加载（scripts/config.sh）
# - 统一工作目录初始化（WORKDIR）
# - 统一 repos.txt 解析（兼容历史格式）
# - 统一 API 版本解析（old/new）
# - 统一 GitLab API 请求与 JSON 校验（避免 HTML 重定向/非 JSON 响应导致脚本误判）
# - 统一 members 分页拉取逻辑（兼容 v3/v4 差异，并避免旧版忽略 page 参数导致死循环）
#
# 约定：
# - 运行时工作目录由 `config.sh` 的 WORKDIR 控制（默认 `./gitlab-migration`）
# - 所有 step 脚本都会 `init_workdir` 后在工作目录内读写 repos.txt/users.txt 等文件
# - 本文件不直接“执行步骤”，只提供函数
#
# 常用函数速览：
# - load_config                 加载 scripts/config.sh（不存在则提示复制模板）
# - init_workdir                创建并进入 WORKDIR
# - fix_repos_txt               修复 repos.txt 末尾无换行导致 while read 漏行的问题
# - read_repo_fields            解析 repos.txt 行，输出到 REPO_* 变量（兼容旧格式）
# - resolve_api_version         读取 OLD_GITLAB_API_VERSION / NEW_GITLAB_API_VERSION
# - urlencode                   URL 编码（GitLab API 路径参数必须编码斜杠）
# - gitlab_curl_json            发起 API 请求并校验 JSON（检测登录页/重定向）
# - gitlab_fetch_members        拉取 members/members(all) 的分页列表（逐行输出 JSON 对象）
# - resolve_user_namespace_id   解析目标实例用户 namespace_id（用于创建个人项目）
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

  # v4: namespace.kind 会明确给出 group/user
  kind=$(echo "$namespace_json" | jq -r '.kind // empty')
  if [[ -n "$kind" ]]; then
    echo "$kind"
    return 0
  fi

  # v3（以及部分旧响应）可能没有 kind，需要通过 owner_id 推断：
  # - owner_id 为空：更像 group namespace
  # - owner_id 有值：更像 user namespace（个人项目）
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

  # 迁移脚本依赖 JSON；但在以下场景 GitLab/反向代理常返回 HTML：
  # - Token 无效或权限不足，被重定向到登录页
  # - API 版本不匹配（例如对 11+ 访问 v3）
  # - 路径未 URL 编码（group/project 的斜杠导致路由错误/重定向）
  # 因此这里做“快速 HTML 识别”，避免把 HTML 当 JSON 继续 jq 解析。
  if [[ "$resp" == \<html* ]] || [[ "$resp" == *"You are being"* ]]; then
    echo "[ERROR] API 返回 HTML 重定向，而非 JSON: ${gitlab_url}/api/${api_version}${api_path}" >&2
    echo "[ERROR] 常见原因: group/project 路径未 URL 编码，或 API 版本与实例不匹配" >&2
    return 1
  fi

  # 严格校验 JSON：如果不是 JSON，直接报错并打印响应片段，方便定位权限/网关报错。
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

    # 不足一页视为最后一页：
    # - 大多数端点会在最后一页返回 < per_page 的数量
    # - 更关键的是：旧版 v3 有时会忽略 page 参数，导致每次都返回同一页（永远 length==100）
    #   这里用“<100 则停止”的策略避免死循环；代价是如果服务端真的总是 100/页但最后一页也 100，
    #   可能需要改用响应头分页信息（但旧版并不总提供），因此当前策略更偏“迁移稳定性优先”。
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
