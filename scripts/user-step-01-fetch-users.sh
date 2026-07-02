#!/usr/bin/env bash
#
# 用户迁移步骤 1: 收集有项目访问权的用户
#
# 1. 从 repos.txt 唯一 group 拉取 Group 成员（继承权限的主要来源）
# 2. 逐项目拉取 owner / 直接成员（覆盖个人项目等场景）
#
# 依赖: curl, jq
# 输入: gitlab-migration/repos.txt
# 输出: gitlab-migration/users.txt
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir
fix_repos_txt

OLD_API=$(resolve_api_version old)

if [[ ! -s repos.txt ]]; then
  echo "[ERROR] repos.txt 不存在或为空"
  echo "请先执行: ./gitlab-migrate.sh 1"
  exit 1
fi

echo "[INFO] USER STEP 1: Fetch users with project access (api/${OLD_API})..."

declare -A seen_user_ids
declare -A processed_groups

record_user_id() {
  local uid=$1
  [[ -n "$uid" && "$uid" != "null" ]] && seen_user_ids["$uid"]=1
}

# 按 username 精确匹配用户 id（v3 的 ?username= 可能返回多用户列表）
lookup_user_id_by_username() {
  local username=$1
  local resp

  resp=$(gitlab_curl_json "$OLD_GITLAB" "$OLD_TOKEN" "$OLD_API" \
    "/users?username=$(urlencode "$username")" 2>/dev/null) || return 1

  echo "$resp" | jq -r --arg u "$username" '
    if type == "array" then
      ([.[] | select(.username == $u)] | .[0].id // empty)
    else
      (.id // empty)
    end
  '
}

count_seen_users() {
  local n=0
  for _k in "${!seen_user_ids[@]}"; do
    n=$((n + 1))
  done
  echo "$n"
}

# 从 members API 路径拉取成员；返回本次新增的用户数
ingest_members() {
  local members_path=$1
  local label=$2
  local before
  before=$(count_seen_users)
  local fetch_status=0

  while IFS= read -r member; do
    [[ -z "$member" ]] && continue
    record_user_id "$(echo "$member" | jq -r '.id')"
  done < <(gitlab_fetch_members "$OLD_GITLAB" "$OLD_TOKEN" "$OLD_API" "$members_path" || fetch_status=1)

  local added=$(($(count_seen_users) - before))
  if [[ "$fetch_status" -ne 0 ]]; then
    echo "[WARN] 拉取失败: ${label} (${members_path})"
    return 1
  fi

  echo "[INFO] ${label}: +${added} user(s)"
  return 0
}

# 拉取 Group 成员；依次尝试 path、numeric id；v4 额外尝试 members/all
ingest_group_members() {
  local group_path=$1
  local group_id=$2
  local group_encoded

  [[ -n "$group_path" ]] || return 0

  if [[ -z "$group_id" ]]; then
    group_id=$(gitlab_curl_json "$OLD_GITLAB" "$OLD_TOKEN" "$OLD_API" \
      "/groups/$(urlencode "$group_path")" 2>/dev/null | jq -r '.id // empty') || group_id=""
  fi

  group_encoded=$(urlencode "$group_path")

  if [[ "$OLD_API" == "v4" ]]; then
    ingest_members "/groups/${group_encoded}/members/all" "group ${group_path} members/all" || true
    [[ -n "$group_id" ]] && ingest_members "/groups/${group_id}/members/all" "group ${group_id} members/all" || true
  fi

  ingest_members "/groups/${group_encoded}/members" "group ${group_path} members" || true
  [[ -n "$group_id" ]] && ingest_members "/groups/${group_id}/members" "group id ${group_id} members" || true
}

# 项目 owner / creator（个人项目 members 常为 []）
ingest_project_owners() {
  local project_detail=$1
  local project_path=$2
  local before
  before=$(count_seen_users)
  local uid kind owner_id username

  while IFS= read -r uid; do
    record_user_id "$uid"
  done < <(echo "$project_detail" | jq -r '
    [.owner.id, .creator_id] | map(select(. != null)) | unique[] | tostring
  ')

  kind=$(echo "$project_detail" | jq -r '.namespace.kind // empty')
  [[ "$kind" == "user" || "$kind" == "" && $(echo "$project_detail" | jq -r '.namespace.owner_id // empty') != "" ]] || return 0

  owner_id=$(echo "$project_detail" | jq -r '.namespace.owner_id // empty')
  record_user_id "$owner_id"

  username=$(echo "$project_detail" | jq -r '.namespace.path // empty')
  [[ -n "$username" ]] || return 0

  record_user_id "$(lookup_user_id_by_username "$username" || true)"

  local added=$(($(count_seen_users) - before))
  if [[ "$added" -gt 0 ]]; then
    echo "[INFO] ${project_path} owners: +${added} user(s)"
  fi
}

# 阶段 A: 仅为 group 命名空间拉取成员（个人项目无 Group）
echo "[INFO] Phase A: group members from repos.txt"
while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "${line:-}" ]] && continue
  read_repo_fields "$line"

  [[ "$REPO_KIND" == "group" ]] || continue
  [[ -n "${processed_groups[$REPO_NAMESPACE]:-}" ]] && continue
  processed_groups["$REPO_NAMESPACE"]=1

  echo "[GROUP] $REPO_NAMESPACE"
  ingest_group_members "$REPO_NAMESPACE" ""
done < repos.txt

# 阶段 B: 逐项目补充 owner 与直接成员
echo "[INFO] Phase B: per-project owners and direct members"
while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "${line:-}" ]] && continue
  read_repo_fields "$line"

  project_path="$REPO_NAMESPACE/$REPO_PROJECT"
  encoded=$(urlencode "$project_path")
  echo "[PROJECT] $project_path"

  project_detail=$(gitlab_curl_json "$OLD_GITLAB" "$OLD_TOKEN" "$OLD_API" "/projects/${encoded}" 2>/dev/null) || project_detail="{}"
  ingest_project_owners "$project_detail" "$project_path"

  if [[ "$OLD_API" == "v4" ]]; then
    ingest_members "/projects/${encoded}/members/all" "project ${project_path} members/all" \
      || ingest_members "/projects/${encoded}/members" "project ${project_path} members" || true
  else
    ingest_members "/projects/${encoded}/members" "project ${project_path} members" || true
  fi

  echo "[INFO] done: $project_path"
done < repos.txt

if [[ $(count_seen_users) -eq 0 ]]; then
  echo "[WARN] 未找到任何项目成员"
  > users.txt
  exit 0
fi

echo "[INFO] Unique user ids collected: $(count_seen_users)"

users_tmp=$(mktemp)
: > "$users_tmp"
skipped=0
fetched=0

for uid in "${!seen_user_ids[@]}"; do
  detail=""
  if ! detail=$(gitlab_curl_json "$OLD_GITLAB" "$OLD_TOKEN" "$OLD_API" "/users/$uid" 2>/dev/null); then
    echo "[WARN] 无法拉取用户详情 id=$uid，已跳过"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$(echo "$detail" | jq -r '.bot // false')" == "true" ]]; then
    username=$(echo "$detail" | jq -r '.username // "unknown"')
    echo "[SKIP] bot user: $username (id=$uid)"
    skipped=$((skipped + 1))
    continue
  fi

  state=$(echo "$detail" | jq -r '.state // "active"')
  if [[ "$state" != "active" ]]; then
    username=$(echo "$detail" | jq -r '.username // "unknown"')
    echo "[SKIP] inactive user: $username (state=$state)"
    skipped=$((skipped + 1))
    continue
  fi

  username=$(echo "$detail" | jq -r '.username')
  email=$(echo "$detail" | jq -r '.email // empty')
  name=$(echo "$detail" | jq -r '.name // empty')

  if [[ -z "$email" ]]; then
    echo "[WARN] no email for user: $username (id=$uid), skipped"
    skipped=$((skipped + 1))
    continue
  fi

  echo "$uid|$username|$email|$name|$state" >> "$users_tmp"
  fetched=$((fetched + 1))
done

mv "$users_tmp" users.txt

echo "[INFO] Users collected: $fetched (skipped: $skipped)"
echo "[INFO] Output: users.txt ($(wc -l < users.txt | tr -d ' ') lines)"
