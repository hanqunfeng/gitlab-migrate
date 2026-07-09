#!/usr/bin/env bash
#
# 步骤 2：在新 GitLab 创建 Group（仅处理 group namespace）
#
# 目标：
# - 读取步骤 1 生成的 `repos.txt`，对其中 `namespace_kind=group` 的 namespace 在新实例创建同名 Group
# - `namespace_kind=user`（个人项目）对应的是“用户 namespace”，**不应创建 Group**，否则会与 username 冲突
#
# 输入文件（位于 WORKDIR，默认 `./gitlab-migration`）：
# - repos.txt
#
# 输出文件（位于 WORKDIR）：
# - groups_created.txt：记录本次新创建的 Group path（便于审计/排错）
#
# 依赖：
# - curl、jq
#
# 行为与重跑语义：
# - 脚本会对每个 group namespace 去重处理（同一个 namespace 只处理一次）
# - 若 Group 已存在则输出 [SKIP] 并跳过；可安全重复执行（幂等）
#
# 风险与注意：
# - 该步骤会通过 API 在目标实例创建资源（写入操作）
# - 如果你误把个人 namespace 当成 Group 创建，会导致后续“创建同名用户失败”
#   （因为 GitLab 的 username 与顶级 group path 共享命名空间）
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
