#!/usr/bin/env bash
#
# 步骤 3: 在新 GitLab 创建 Project
#
# 为 repos.txt 中的每个项目在对应 group 下创建空仓库。
# 使用 group/project 路径精确查询，避免不同 group 下同名 project 误判。
#
# 依赖: curl, jq
# 输入: gitlab-migration/repos.txt
# 输出: gitlab-migration/projects_created.txt（本次新创建的 project 记录）
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir
fix_repos_txt

echo "[INFO] STEP 3: Creating projects..."

while IFS='|' read -r group project repo || [[ -n "${group:-}" ]]; do
  [[ -z "${group:-}" ]] && continue

  echo "[PROJECT] $group/$project"

  # 按 group 路径精确获取 namespace id（不用模糊 search）
  group_id=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/v4/groups/$(urlencode "$group")" | jq '.id // empty')

  if [[ -z "$group_id" ]]; then
    echo "[ERROR] group not found: $group"
    continue
  fi

  # 按 group/project 完整路径查询，404 表示不存在
  project_path="$group/$project"
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/v4/projects/$(urlencode "$project_path")")

  if [[ "$status" == "404" ]]; then

    curl -s --request POST \
      --header "PRIVATE-TOKEN: $NEW_TOKEN" \
      --data "name=$project&namespace_id=$group_id" \
      "$NEW_GITLAB/api/v4/projects" > /dev/null

    echo "$group/$project" >> projects_created.txt
    echo "[CREATED] project: $group/$project"

  elif [[ "$status" == "200" ]]; then
    echo "[SKIP] project exists: $group/$project"
  else
    echo "[ERROR] check failed for $group/$project (HTTP $status)"
  fi

done < repos.txt
