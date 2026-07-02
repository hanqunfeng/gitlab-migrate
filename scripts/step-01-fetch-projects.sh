#!/usr/bin/env bash
#
# 步骤 1: 从旧 GitLab 拉取全部项目列表
#
# 通过 GitLab API 分页获取所有项目，写入 repos.txt。
# 每行格式: namespace_kind|namespace|project|http_url_to_repo
#   namespace_kind: group | user（个人项目）
#
# 依赖: curl, jq
# 输出: gitlab-migration/repos.txt
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

OLD_API=$(resolve_api_version old)

echo "[INFO] STEP 1: Fetch ALL projects (api/${OLD_API}, pagination safe)"

> repos.txt

page=1
per_page=100

while true; do
  echo "[INFO] fetching page $page"

  resp=$(curl -s --header "PRIVATE-TOKEN: $OLD_TOKEN" \
    "$OLD_GITLAB/api/${OLD_API}/projects?per_page=$per_page&page=$page&simple=true")

  count=$(echo "$resp" | jq 'length // 0')

  if [ "$count" -eq 0 ]; then
    break
  fi

  echo "$resp" | jq -r --arg old_api "$OLD_API" '
    .[] |
    .namespace as $ns |
    (
      if $ns.kind then $ns.kind
      elif ($ns.owner_id == null) then "group"
      else "user" end
    ) as $kind |
    "\($kind)|\($ns.path)|\(.path)|\(.http_url_to_repo)"
  ' >> repos.txt

  page=$((page + 1))
done

fix_repos_txt

echo "[INFO] Total repos: $(wc -l < repos.txt | tr -d ' ')"
group_count=$(grep -c '^group|' repos.txt 2>/dev/null || echo 0)
user_count=$(grep -c '^user|' repos.txt 2>/dev/null || echo 0)
echo "[INFO] group namespace: $group_count, user namespace: $user_count"
