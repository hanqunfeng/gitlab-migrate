#!/usr/bin/env bash
#
# 步骤 1: 从旧 GitLab 拉取全部项目列表
#
# 通过 GitLab API 分页获取所有项目，写入 repos.txt。
# 每行格式: group|project|http_url_to_repo
#
# 依赖: curl, jq
# 输出: gitlab-migration/repos.txt
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

echo "[INFO] STEP 1: Fetch ALL projects (pagination safe)"

# 每次执行前清空，避免重复追加
> repos.txt

page=1
per_page=100  # GitLab API 单页最大 100

while true; do
  echo "[INFO] fetching page $page"

  # simple=true 减少响应体积；使用源实例 API 拉取项目列表
  resp=$(curl -s --header "PRIVATE-TOKEN: $OLD_TOKEN" \
    "$OLD_GITLAB/api/v3/projects?per_page=$per_page&page=$page&simple=true")

  count=$(echo "$resp" | jq length)

  # 返回空数组表示已无更多页
  if [ "$count" -eq 0 ]; then
    break
  fi

  # 提取 namespace、项目名、HTTP 克隆地址，追加到 repos.txt
  echo "$resp" | jq -r '.[] | "\(.namespace.path)|\(.path)|\(.http_url_to_repo)"' \
    >> repos.txt

  page=$((page + 1))
done

# 确保文件末尾有换行符，供后续 while read 正确解析
fix_repos_txt

echo "[INFO] Total repos: $(wc -l < repos.txt)"
