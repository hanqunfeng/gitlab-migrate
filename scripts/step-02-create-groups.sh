#!/usr/bin/env bash
#
# 步骤 2: 在新 GitLab 创建 Group
#
# 仅为 namespace_kind=group 的命名空间创建 Group；个人项目（user）跳过。
#
# 依赖: curl, jq
# 输入: gitlab-migration/repos.txt
# 输出: gitlab-migration/groups_created.txt
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir
fix_repos_txt

NEW_API=$(resolve_api_version new)

echo "[INFO] STEP 2: Creating groups (skip user namespaces)..."

declare -A processed_groups

while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "${line:-}" ]] && continue
  read_repo_fields "$line"

  if [[ "$REPO_KIND" == "user" ]]; then
    echo "[SKIP] user namespace, no group: $REPO_NAMESPACE/$REPO_PROJECT"
    continue
  fi

  [[ -n "${processed_groups[$REPO_NAMESPACE]:-}" ]] && continue
  processed_groups["$REPO_NAMESPACE"]=1

  echo "[GROUP] $REPO_NAMESPACE"

  exists=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/${NEW_API}/groups?search=$REPO_NAMESPACE" | jq 'length // 0')

  if [[ "$exists" -eq 0 ]]; then
    curl -s --request POST \
      --header "PRIVATE-TOKEN: $NEW_TOKEN" \
      --data "name=$REPO_NAMESPACE&path=$REPO_NAMESPACE" \
      "$NEW_GITLAB/api/${NEW_API}/groups" > /dev/null

    echo "$REPO_NAMESPACE" >> groups_created.txt
    echo "[CREATED] group: $REPO_NAMESPACE"
  else
    echo "[SKIP] group exists: $REPO_NAMESPACE"
  fi

done < repos.txt
