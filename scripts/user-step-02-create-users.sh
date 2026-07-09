#!/usr/bin/env bash
#
# 用户迁移步骤 2：在新实例创建本地用户（生成 users_mapped.txt）
#
# 目标：
# - 读取步骤 1 生成的 users.txt
# - 在新 GitLab 上创建用户账号；若用户已存在，则建立“旧 id → 新 id”映射
# - 该映射文件将被步骤 3 用于成员同步（把旧实例成员的 user_id 映射到新实例 user_id）
#
# 输入文件（位于 WORKDIR，默认 `./gitlab-migration`）：
# - users.txt：old_id|username|email|name|state
#
# 输出文件（位于 WORKDIR）：
# - users_mapped.txt：old_id|new_id|username|email
# - users_created.txt：本次新创建的用户名（用于审计/通知/回滚）
#
# 依赖：
# - curl、jq
#
# 创建策略与安全性：
# - 创建用户使用：reset_password=true + skip_confirmation=true
#   - reset_password=true：由 GitLab 发送“重置密码”邮件（避免脚本直接生成/暴露初始密码）
#   - skip_confirmation=true：跳过邮箱确认（便于批量迁移；前提是你信任 users.txt 的 email 来源）
#
# username 冲突处理（常见迁移坑）：
# - GitLab 的 username 与顶级 group path 共享命名空间
# - 如果目标实例上存在同名 Group（例如误把个人 namespace 当成 Group 创建），会导致无法创建同名用户
# - 脚本会检测 group path 冲突并尝试备用 username（如 `${username}-user` 或 display_name）
#
# 重跑语义：
# - 每次执行会覆盖 users_mapped.txt / users_created.txt
# - 已存在用户会被映射并跳过创建；重复执行安全
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

NEW_API=$(resolve_api_version new)

if [[ ! -s users.txt ]]; then
  echo "[ERROR] users.txt 不存在或为空"
  echo "请先执行: ./gitlab-migrate-users.sh 1"
  exit 1
fi

echo "[INFO] USER STEP 2: Creating users on new GitLab (api/${NEW_API})..."

> users_mapped.txt
> users_created.txt

created=0
mapped=0
failed=0

# 从 users?username= 或 users?search= 响应中解析 user id（兼容数组/单对象）
parse_user_id_from_lookup() {
  local resp=$1
  echo "$resp" | jq -r 'if type == "array" then .[0].id // empty else .id // empty end'
}

# 按 username 或 email 查找新实例已有用户
find_new_user_id() {
  local username=$1
  local email=$2
  local resp uid

  resp=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/${NEW_API}/users?username=$(urlencode "$username")")
  uid=$(parse_user_id_from_lookup "$resp")
  [[ -n "$uid" ]] && echo "$uid" && return 0

  resp=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/${NEW_API}/users?search=$(urlencode "$email")")
  uid=$(echo "$resp" | jq -r --arg email "$email" '
    if type == "array" then
      ([.[] | select(.email == $email)] | .[0].id // empty)
    else empty end
  ')
  [[ -n "$uid" ]] && echo "$uid" && return 0

  return 1
}

# 检查顶级 path 是否已被 Group 占用（与用户 username 冲突）
group_path_exists() {
  local path=$1
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/${NEW_API}/groups/$(urlencode "$path")")
  [[ "$status" == "200" ]]
}

# 尝试创建用户；成功时输出 new_id 到 stdout
try_create_user() {
  local username=$1
  local email=$2
  local name=$3
  local http_code new_id

  # 将创建用户接口的响应体落到临时文件，避免：
  # - curl 输出与脚本 stdout 混杂（影响后续解析/日志阅读）
  # - 失败时无法获取 message/error 细节
  # 注意：这里固定写到 /tmp；如需更严格可用 mktemp + trap 清理。
  http_code=$(curl -s -o /tmp/gitlab_user_create_resp.json -w "%{http_code}" \
    --request POST \
    --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    --data "email=$(urlencode "$email")&username=$(urlencode "$username")&name=$(urlencode "$name")&reset_password=true&skip_confirmation=true" \
    "$NEW_GITLAB/api/${NEW_API}/users")

  if [[ "$http_code" == "201" ]]; then
    new_id=$(jq -r '.id' /tmp/gitlab_user_create_resp.json)
    echo "$new_id"
    return 0
  fi

  return 1
}

# 生成备用 username（Group 路径已占用时）
suggest_alt_usernames() {
  local username=$1
  local display_name=$2

  if [[ -n "$display_name" && "$display_name" != "$username" ]]; then
    echo "$display_name"
  fi
  echo "${username}-user"
}

map_existing_user() {
  local old_id=$1
  local new_id=$2
  local username=$3
  local email=$4
  local label=$5

  echo "$old_id|$new_id|$username|$email" >> users_mapped.txt
  echo "[SKIP] $label: $username (new_id=$new_id)"
  mapped=$((mapped + 1))
}

while IFS='|' read -r old_id username email name _state || [[ -n "${old_id:-}" ]]; do
  [[ -z "${old_id:-}" ]] && continue

  echo "[USER] $username ($email)"

  existing_id=$(find_new_user_id "$username" "$email" || true)

  if [[ -n "$existing_id" ]]; then
    map_existing_user "$old_id" "$existing_id" "$username" "$email" "user exists"
    continue
  fi

  if group_path_exists "$username"; then
    echo "[WARN] 顶级路径 '$username' 已被 Group 占用（常见于个人项目 namespace 被当作 Group 迁移）"
    echo "[WARN] 将尝试备用 username 创建用户"
  fi

  new_id=$(try_create_user "$username" "$email" "$name" || true)

  if [[ -n "$new_id" ]]; then
    echo "$old_id|$new_id|$username|$email" >> users_mapped.txt
    echo "$username" >> users_created.txt
    echo "[CREATED] user: $username (new_id=$new_id)"
    created=$((created + 1))
    continue
  fi

  # 创建失败：若 username 冲突，尝试备用名
  err_msg=$(jq -r '.message // .error // empty' /tmp/gitlab_user_create_resp.json 2>/dev/null || true)
  username_taken=false
  if echo "$err_msg" | grep -qi 'username\|用户名\|已经被使用\|already'; then
    username_taken=true
  fi

  resolved=false
  if [[ "$username_taken" == "true" ]]; then
    # 先再查一遍“是否其实已存在”（并发创建、或前一步创建成功但本地判断失败等边缘场景）
    alt_id=$(find_new_user_id "$username" "$email" || true)
    if [[ -n "$alt_id" ]]; then
      map_existing_user "$old_id" "$alt_id" "$username" "$email" "user exists (found after conflict)"
      resolved=true
    else
      # 备用 username 策略：
      # - 优先 display_name（若可用且不等于 username）
      # - 再尝试 `${username}-user`
      # 用于绕过“username 与 group 顶级 path 冲突”或“用户名被占用”的问题。
      while read -r alt_username; do
        [[ -z "$alt_username" || "$alt_username" == "$username" ]] && continue
        [[ "$(find_new_user_id "$alt_username" "$email" || true)" != "" ]] && continue

        echo "[INFO] 尝试备用 username: $alt_username"
        new_id=$(try_create_user "$alt_username" "$email" "$name" || true)
        if [[ -n "$new_id" ]]; then
          echo "$old_id|$new_id|$alt_username|$email" >> users_mapped.txt
          echo "$alt_username" >> users_created.txt
          echo "[CREATED] user: $alt_username (原 username=$username 与 Group 冲突, new_id=$new_id)"
          created=$((created + 1))
          resolved=true
          break
        fi
      done < <(suggest_alt_usernames "$username" "$name")
    fi
  fi

  if [[ "$resolved" == "false" ]]; then
    err_msg=$(jq -r '.message // .error // "unknown error"' /tmp/gitlab_user_create_resp.json 2>/dev/null || echo "unknown error")
    echo "[FAIL] create user $username (HTTP error): $err_msg"
    if group_path_exists "$username"; then
      echo "[HINT] Group '$username' 已存在，无法使用同名 username。可删除该 Group 或手动指定备用用户名。"
    fi
    failed=$((failed + 1))
  fi

done < users.txt

echo "[INFO] Created: $created, mapped existing: $mapped, failed: $failed"
echo "[INFO] Output: users_mapped.txt ($(wc -l < users_mapped.txt | tr -d ' ') lines)"
