#!/usr/bin/env bash
#
# 用户迁移步骤 3：同步 Group 与 Project 成员关系到新实例
#
# 目标：
# - 从旧实例读取成员列表（read）：Group/Project 的直接成员
# - 向新实例写入成员关系（write）：尽量复刻旧实例的 access_level / expires_at
# - 对已存在成员：若现有权限 >= 目标权限则跳过；否则尝试提升
#
# 为什么先同步 Group 再同步 Project：
# - Group 成员是多数权限继承的来源（很多项目的权限来自 group）
# - 再同步 Project 直接成员可以覆盖/提升继承权限（例如某人是 group Developer，但在某项目是 Maintainer）
#
# 输入文件（位于 WORKDIR，默认 `./gitlab-migration`）：
# - repos.txt：项目清单（来自 `./gitlab-migrate.sh 1`）
# - users_mapped.txt：旧 id → 新 id 映射（来自 `./gitlab-migrate-users.sh 2`）
#
# 输出文件（位于 WORKDIR）：
# - members_fail.log：写入成员失败的详细错误（包含 API message/error）
#
# 依赖：
# - curl、jq
#
# 权限与前置条件：
# - 目标实例的对应 group/project 必须已存在（建议先完成 `./gitlab-migrate.sh 2 3`）
# - `NEW_TOKEN` 需要有管理员权限或足够的成员管理权限（能 POST/PUT members）
#
# 重跑语义：
# - 可重复执行：
#   - 已存在且权限足够的成员会被跳过
#   - 权限不足的成员会再次尝试提升
# - members_fail.log 每次执行会被清空重写（方便定位“本次”失败项）
#
# 常见失败原因（members_fail.log 可见）：
# - 用户未创建/映射缺失（users_mapped.txt 找不到 old_id）
# - 目标资源不存在（group/project path 不存在或编码不正确）
# - NEW_TOKEN 权限不足（无法管理成员）
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir
fix_repos_txt

OLD_API=$(resolve_api_version old)
NEW_API=$(resolve_api_version new)

if [[ ! -s repos.txt ]]; then
  echo "[ERROR] repos.txt 不存在或为空"
  exit 1
fi

if [[ ! -s users_mapped.txt ]]; then
  echo "[ERROR] users_mapped.txt 不存在或为空"
  echo "请先执行: ./gitlab-migrate-users.sh 2"
  exit 1
fi

echo "[INFO] USER STEP 3: Syncing members (read api/${OLD_API}, write api/${NEW_API})..."

> members_fail.log

# 根据旧 user id 查新 user id
map_user_id() {
  local old_id=$1
  # users_mapped.txt 的格式：old_id|new_id|username|email
  # 这里用 awk 做一次“快速查表”，避免每条成员都用 curl 查询新实例（大幅降低 API 压力）。
  awk -F'|' -v id="$old_id" '$1 == id { print $2; exit }' users_mapped.txt
}

# 分页拉取成员列表（api_path 形如 /projects/group%2Fproject/members）
fetch_members() {
  local api_path=$1
  gitlab_fetch_members "$OLD_GITLAB" "$OLD_TOKEN" "$OLD_API" "$api_path"
}

# 向 Group 或 Project 添加成员；已存在则尝试提升 access_level
add_member() {
  local resource_type=$1   # groups | projects
  local resource_path=$2
  local new_user_id=$3
  local access_level=$4
  local expires_at=${5:-}

  local base_url="$NEW_GITLAB/api/${NEW_API}/${resource_type}/$(urlencode "$resource_path")/members"
  local member_url="${base_url}/${new_user_id}"

  # 先 GET 一次成员详情，判断是否已存在以及当前 access_level：
  # - 若已存在且当前权限 >= 目标权限：跳过（幂等）
  # - 若已存在但权限更低：PUT 提升权限
  # - 若不存在：POST 新增成员
  local current
  current=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" "$member_url")
  local current_level
  current_level=$(echo "$current" | jq -r '.access_level // empty')

  local post_data="user_id=${new_user_id}&access_level=${access_level}"
  if [[ -n "$expires_at" && "$expires_at" != "null" ]]; then
    post_data="${post_data}&expires_at=$(urlencode "$expires_at")"
  fi

  if [[ -n "$current_level" ]]; then
    if [[ "$current_level" -ge "$access_level" ]]; then
      echo "[SKIP] member exists: ${resource_path} user_id=${new_user_id} (level=${current_level})"
      return 0
    fi

    # 已存在但权限较低，尝试提升
    local put_code
    put_code=$(curl -s -o /tmp/gitlab_member_resp.json -w "%{http_code}" \
      --request PUT \
      --header "PRIVATE-TOKEN: $NEW_TOKEN" \
      --data "access_level=${access_level}" \
      "$member_url")

    if [[ "$put_code" == "200" ]]; then
      echo "[UPDATED] ${resource_path} user_id=${new_user_id} -> level ${access_level}"
      return 0
    fi

    local err_msg
    err_msg=$(jq -r '.message // .error // "unknown error"' /tmp/gitlab_member_resp.json 2>/dev/null || echo "unknown error")
    echo "[FAIL] update member ${resource_path} user_id=${new_user_id}: $err_msg" | tee -a members_fail.log
    return 1
  fi

  local post_code
  post_code=$(curl -s -o /tmp/gitlab_member_resp.json -w "%{http_code}" \
    --request POST \
    --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    --data "$post_data" \
    "$base_url")

  if [[ "$post_code" == "201" ]]; then
    echo "[ADDED] ${resource_path} user_id=${new_user_id} level=${access_level}"
    return 0
  fi

  local err_msg
  err_msg=$(jq -r '.message // .error // "unknown error"' /tmp/gitlab_member_resp.json 2>/dev/null || echo "unknown error")
  echo "[FAIL] add member ${resource_path} user_id=${new_user_id}: $err_msg" | tee -a members_fail.log
  return 1
}

sync_members_for_resource() {
  local resource_type=$1
  local resource_path=$2
  local members_path="/${resource_type}/$(urlencode "$resource_path")/members"

  echo "[${resource_type}] $resource_path"

  # 旧实例 members API 返回的是“直接成员”。对于 v3 来说没有 members/all，
  # 因此脚本按“先 group 再 project”的顺序同步，最大化还原权限体系。
  while IFS= read -r member; do
    [[ -z "$member" ]] && continue

    local old_user_id access_level expires_at new_user_id
    old_user_id=$(echo "$member" | jq -r '.id')
    access_level=$(echo "$member" | jq -r '.access_level')
    expires_at=$(echo "$member" | jq -r '.expires_at // empty')

    new_user_id=$(map_user_id "$old_user_id")
    if [[ -z "$new_user_id" ]]; then
      local uname
      uname=$(echo "$member" | jq -r '.username // "unknown"')
      echo "[WARN] no mapping for user $uname (old_id=$old_user_id), skipped"
      continue
    fi

    add_member "$resource_type" "$resource_path" "$new_user_id" "$access_level" "$expires_at" || true
  done < <(fetch_members "$members_path")
}

# 阶段 A: 同步 Group 直接成员（跳过 user 命名空间）
echo "[INFO] Phase A: sync group members"
while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "${line:-}" ]] && continue
  read_repo_fields "$line"
  [[ "$REPO_KIND" == "group" ]] || continue
  echo "$REPO_NAMESPACE"
done < repos.txt | sort -u | while read -r group || [[ -n "${group:-}" ]]; do
  [[ -z "${group:-}" ]] && continue
  sync_members_for_resource "groups" "$group"
done

# 阶段 B: 同步 Project 直接成员
echo "[INFO] Phase B: sync project members"
while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "${line:-}" ]] && continue
  read_repo_fields "$line"
  sync_members_for_resource "projects" "$REPO_NAMESPACE/$REPO_PROJECT"
done < repos.txt

fail_count=0
[[ -f members_fail.log ]] && fail_count=$(wc -l < members_fail.log | tr -d ' ')

echo "[INFO] Member sync done. failures: $fail_count"
if [[ "$fail_count" -gt 0 ]]; then
  echo "[INFO] See members_fail.log for details"
fi
