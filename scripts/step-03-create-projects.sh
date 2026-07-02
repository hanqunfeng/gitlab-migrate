#!/usr/bin/env bash
#
# 步骤 3: 在新 GitLab 创建 Project
#
# group 项目：创建在对应 Group 下。
# user 项目：创建在对应用户个人命名空间下（须已存在该用户，建议先执行用户迁移步骤 2）。
#
# 依赖: curl, jq
# 输入: gitlab-migration/repos.txt
# 输出: gitlab-migration/projects_created.txt, projects_skipped_user.txt
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
    namespace_id=$(resolve_user_namespace_id "$REPO_NAMESPACE" || true)
    if [[ -z "$namespace_id" ]]; then
      echo "[SKIP] user not found on new GitLab: $REPO_NAMESPACE (先执行 ./gitlab-migrate-users.sh 2)"
      echo "$project_path|$REPO_NAMESPACE" >> projects_skipped_user.txt
      continue
    fi
  else
    namespace_id=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
      "$NEW_GITLAB/api/${NEW_API}/groups/$(urlencode "$REPO_NAMESPACE")" | jq '.id // empty')

    if [[ -z "$namespace_id" ]]; then
      echo "[ERROR] group not found: $REPO_NAMESPACE"
      continue
    fi
  fi

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
