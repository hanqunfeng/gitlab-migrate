#!/usr/bin/env bash
#
# 步骤 2: 在新 GitLab 创建 Group
#
# 从 repos.txt 提取所有唯一的 group（namespace），在新 GitLab 上逐个创建。
# 已存在的 group 会跳过（幂等）。
#
# 依赖: curl, jq
# 输入: gitlab-migration/repos.txt
# 输出: gitlab-migration/groups_created.txt（本次新创建的 group 记录）
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir
fix_repos_txt

echo "[INFO] STEP 2: Creating groups..."

# 使用进程替换而非管道，避免 while 在子 shell 中运行导致副作用异常
while read -r group || [[ -n "${group:-}" ]]; do
  [[ -z "${group:-}" ]] && continue

  echo "[GROUP] $group"

  # 模糊搜索 group 是否已存在
  exists=$(curl -s --header "PRIVATE-TOKEN: $NEW_TOKEN" \
    "$NEW_GITLAB/api/v4/groups?search=$group" | jq 'length // 0')

  if [[ "$exists" -eq 0 ]]; then
    curl -s --request POST \
      --header "PRIVATE-TOKEN: $NEW_TOKEN" \
      --data "name=$group&path=$group" \
      "$NEW_GITLAB/api/v4/groups" > /dev/null

    echo "$group" >> groups_created.txt
    echo "[CREATED] group: $group"
  else
    echo "[SKIP] group exists: $group"
  fi

done < <(cut -d'|' -f1 repos.txt | sort -u)
