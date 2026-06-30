#!/usr/bin/env bash
#
# 步骤 4: Mirror Clone 源仓库
#
# 从旧 GitLab 以 --mirror 方式克隆裸仓库到本地 WORKDIR。
# 目录结构: {group}/{project}.git/
#
# 依赖: git, jq（config.sh）
# 输入: gitlab-migration/repos.txt
# 输出: gitlab-migration/{group}/{project}.git/
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir
fix_repos_txt

echo "[INFO] STEP 4: mirror clone"

while IFS='|' read -r group project repo || [[ -n "${group:-}" ]]; do
  [[ -z "${group:-}" ]] && continue

  dir="$group/$project.git"

  # 已 clone 过的目录跳过，支持断点续传
  if [ -d "$dir" ]; then
    echo "[SKIP] exists $dir"
    continue
  fi

  echo "[CLONE] $repo"

  # 使用 OLD_TOKEN 认证；用户名 oauth2 为 GitLab PAT 惯例占位符
  git -c "credential.helper=!f() { echo \"username=oauth2\"; echo \"password=${OLD_TOKEN}\"; }; f" \
    clone --mirror "$repo" "$dir"

done < repos.txt
