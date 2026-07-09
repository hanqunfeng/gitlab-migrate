#!/usr/bin/env bash
#
# 步骤 4：Mirror clone 源仓库到本地（生成裸仓库目录）
#
# 目标：
# - 读取 repos.txt 中的 http_url_to_repo，对每个项目执行 `git clone --mirror`
# - mirror 裸仓库会包含所有 refs（branches/tags）与远端配置，适合后续 `git push --mirror`
#
# 输入文件（位于 WORKDIR，默认 `./gitlab-migration`）：
# - repos.txt
#
# 输出目录（位于 WORKDIR）：
# - {namespace}/{project}.git/（裸仓库目录，namespace 可能是 group path 或 username）
#
# 依赖：
# - git
# - curl/jq 不直接使用，但依赖 `scripts/config.sh` 里的 token 等配置
#
# 认证方式：
# - 使用 `OLD_TOKEN` 通过 GitLab 的 HTTP Basic 方式鉴权
# - 用户名固定用 `oauth2`（GitLab 对 PAT 的常见占位用户名），密码为 token
# - 脚本不会在日志中输出 token
#
# 行为与重跑语义：
# - 若本地目标目录已存在则 [SKIP] 并跳过；可安全重跑（断点续传）
# - clone 过程中中断/失败可能留下不完整裸仓库目录，建议删除该目录后重试
#
# 注意：
# - 该步骤对旧实例只有读操作，但会产生大量网络与磁盘 IO（仓库大/数量多时耗时明显）
# - 若旧实例启用了自签证书，可能需要在 git/curl 层面额外处理证书信任
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir
fix_repos_txt

echo "[INFO] STEP 4: mirror clone"

while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "${line:-}" ]] && continue
  read_repo_fields "$line"

  dir="$REPO_NAMESPACE/$REPO_PROJECT.git"

  # 已 clone 过的目录跳过，支持断点续传
  if [ -d "$dir" ]; then
    echo "[SKIP] exists $dir"
    continue
  fi

  echo "[CLONE] $REPO_URL"

  # 使用 OLD_TOKEN 认证；用户名 oauth2 为 GitLab PAT 惯例占位符
  git -c "credential.helper=!f() { echo \"username=oauth2\"; echo \"password=${OLD_TOKEN}\"; }; f" \
    clone --mirror "$REPO_URL" "$dir"

done < repos.txt
