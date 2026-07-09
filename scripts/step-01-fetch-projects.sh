#!/usr/bin/env bash
#
# 步骤 1：从旧 GitLab 拉取项目列表（生成 repos.txt）
#
# 目标：
# - 分页调用旧实例 Projects API，生成后续步骤使用的项目清单 `repos.txt`
# - 清单用于：创建 group/project、mirror clone、push、以及用户/成员收集
#
# 输出文件（位于 WORKDIR，默认 `./gitlab-migration`）：
# - repos.txt
#
# repos.txt 行格式：
# - namespace_kind|namespace|project|http_url_to_repo
#   - namespace_kind：`group`（Group 下项目）或 `user`（个人项目）
#   - namespace：Group path 或 username
#   - project：项目 path（不含 namespace）
#   - http_url_to_repo：HTTP 克隆地址（步骤 4 会用它进行 mirror clone）
#
# 依赖：
# - curl、jq
#
# 重要说明（v3/v4 兼容）：
# - 旧实例 API 版本由 `scripts/config.sh` 的 `OLD_GITLAB_API_VERSION` 控制（v3 或 v4）
# - v4 通常使用 `GET /api/v4/projects` 即可返回“当前 token 用户可见的项目集合”
# - v3 在部分旧版 GitLab 上可能出现：即便用户是管理员，`GET /api/v3/projects` 也拿不到未授权项目。
#   迁移场景更稳妥的方式是使用 `GET /api/v3/projects/all` 拉取更完整的实例项目列表。
#
# 重跑语义：
# - 每次执行都会清空并重新生成 repos.txt（以旧实例当前项目列表为准）
#
# 常见排障：
# - API 返回 HTML（登录页/重定向）：多由 token 无效/权限不足、API 版本不匹配、或被反向代理重定向导致
# - 项目数量较多：脚本按 per_page/page 翻页，直到返回空数组为止
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

  # 旧实例项目列表：
  # - v4: 通常 GET /projects 就能返回当前 token 可见的项目集合
  # - v3: 在部分旧版本上，GET /projects 可能拿不到“未显式授权给该用户”的项目（即便该用户是管理员）
  #      迁移场景更稳妥的是使用 /projects/all 拉取更完整的项目集合
  #
  # 注意：simple=true 用于减少返回字段体积，降低传输与 jq 解析成本；部分 v3 实例可能忽略它。
  resp=$(curl -s --header "PRIVATE-TOKEN: $OLD_TOKEN" \
    "$OLD_GITLAB/api/${OLD_API}/projects/all?per_page=$per_page&page=$page&simple=true")

  count=$(echo "$resp" | jq 'length // 0')

  if [ "$count" -eq 0 ]; then
    break
  fi

  echo "$resp" | jq -r --arg old_api "$OLD_API" '
    .[] |
    .namespace as $ns |
    (
      # v4: 直接使用 namespace.kind
      # v3: 通常没有 kind 字段，通过 namespace.owner_id 推断（owner_id 有值更像 user namespace）
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
