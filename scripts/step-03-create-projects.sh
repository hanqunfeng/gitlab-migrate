#!/usr/bin/env bash
#
# 步骤 3：在新 GitLab 创建 Project（按 repos.txt 逐项创建）
#
# 目标：
# - 读取步骤 1 生成的 `repos.txt`，在新实例创建同路径的项目（仅创建空项目壳，不包含代码）
# - 后续步骤 4/5 会基于同路径将仓库镜像推送到这些项目中
#
# namespace 处理规则：
# - group 项目：创建在对应 Group（namespace_kind=group）下
# - user 项目：创建在对应用户个人命名空间（namespace_kind=user）下
#   - 这要求“目标实例上已存在该用户”，否则无法解析用户 namespace_id
#   - 因此涉及个人项目时，建议先执行：`./gitlab-migrate-users.sh 2`
#
# 输入文件（位于 WORKDIR，默认 `./gitlab-migration`）：
# - repos.txt
#
# 输出文件（位于 WORKDIR）：
# - projects_created.txt：记录本次新创建的项目 path（namespace/project）
# - projects_skipped_user.txt：记录因目标实例缺少用户而跳过的个人项目（用于后续补跑）
#
# 依赖：
# - curl、jq
#
# 行为与重跑语义：
# - 对每个项目会先调用 GET /projects/:encoded_path 判断是否存在（200=存在、404=不存在）
# - 目标项目已存在则 [SKIP]；重复执行安全（幂等）
# - user 项目在找不到用户 namespace_id 时跳过并写入 projects_skipped_user.txt；
#   创建用户后可重跑本步骤以补齐个人项目
#
# 注意：
# - 本步骤只创建“项目壳”，不会迁移 Issue/MR/Wiki/CI 等元数据
# - 项目可见性/默认分支等高级设置使用 GitLab 默认值（可迁移完成后按需调整）
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir
fix_repos_txt

NEW_API=$(resolve_api_version new)

echo "[INFO] STEP 3: Creating projects..."

> projects_skipped_user.txt

while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "${line:-}" ]] && continue
  read_repo_fields "$line"

  project_path="$REPO_NAMESPACE/$REPO_PROJECT"
  echo "[PROJECT] $project_path ($REPO_KIND namespace)"

  namespace_id=""

  if [[ "$REPO_KIND" == "user" ]]; then
    # 个人项目需要创建到“用户个人命名空间”下：
    # - v4 创建项目需要 namespace_id
    # - 用户个人 namespace_id 只有在“用户已存在于目标实例”时才能解析出来
    # 因此个人项目建议先跑：./gitlab-migrate-users.sh 2
    namespace_id=$(resolve_user_namespace_id "$REPO_NAMESPACE" || true)
    if [[ -z "$namespace_id" ]]; then
      echo "[SKIP] user not found on new GitLab: $REPO_NAMESPACE (先执行 ./gitlab-migrate-users.sh 2)"
      echo "$project_path|$REPO_NAMESPACE" >> projects_skipped_user.txt
      continue
    fi
  else
    # group 项目创建到 Group 下：namespace_id 即 group id（GET /groups/:path 的 .id）
    # 注意 group path 可能包含特殊字符，因此需要 urlencode。
    namespace_id=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
      "$NEW_GITLAB/api/${NEW_API}/groups/$(urlencode "$REPO_NAMESPACE")" | jq '.id // empty')

    if [[ -z "$namespace_id" ]]; then
      echo "[ERROR] group not found: $REPO_NAMESPACE"
      continue
    fi
  fi

  # 通过“路径”判断项目是否存在：
  # - 200：项目已存在（跳过，支持幂等）
  # - 404：项目不存在（创建）
  # - 其它：多为权限/网关错误，需要排查 token 与 API 版本
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/${NEW_API}/projects/$(urlencode "$project_path")")

  if [[ "$status" == "404" ]]; then
    curl -s --request POST \
      --header "PRIVATE-TOKEN: $NEW_TOKEN" \
      --data "name=$REPO_PROJECT&namespace_id=$namespace_id" \
      "$NEW_GITLAB/api/${NEW_API}/projects" > /dev/null

    echo "$project_path" >> projects_created.txt
    echo "[CREATED] project: $project_path"
  elif [[ "$status" == "200" ]]; then
    echo "[SKIP] project exists: $project_path"
  else
    echo "[ERROR] check failed for $project_path (HTTP $status)"
  fi

done < repos.txt

if [[ -s projects_skipped_user.txt ]]; then
  echo "[WARN] 个人项目因用户未创建而跳过，见 projects_skipped_user.txt"
  echo "[WARN] 创建用户后重新执行: ./gitlab-migrate.sh 3"
fi
