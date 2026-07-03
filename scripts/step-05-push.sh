#!/usr/bin/env bash
#
# 步骤 5: 并行 Push 到新 GitLab
#
# 将本地 mirror 裸仓库推送到新 GitLab 对应路径。
# 使用 find + xargs 并行执行，并发数由 config.sh 中 CONCURRENCY 控制。
#
# 依赖: git, find, xargs
# 输入: gitlab-migration/{group}/{project}.git/
# 输出: gitlab-migration/success.log, gitlab-migration/fail.log
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

echo "[INFO] STEP 5: push to new GitLab"

push_repo() {
  local dir=${1#./}  # 去掉 find 输出的 ./ 前缀

  # 从路径解析 group 和 project，如 android/tool.git -> group=android, project=tool
  group=$(dirname "$dir")
  project=$(basename "$dir" .git)

  if [[ "$group" == "." ]]; then
    echo "[FAIL] invalid repo path: $1" >> fail.log
    echo "[ERROR] invalid repo path: $1 (missing group)"
    return 1
  fi

  url="$NEW_GITLAB/$group/$project.git"

  echo "[PUSH] $url"

  cd "$dir"

  # 使用 NEW_TOKEN 认证 push；日志中不暴露 token
  git -c "credential.helper=!f() { echo \"username=oauth2\"; echo \"password=${NEW_TOKEN}\"; }; f" \
    push --mirror "$url" \
    && echo "[OK] $group/$project" >> ../../success.log \
    || echo "[FAIL] $group/$project" >> ../../fail.log

  cd - > /dev/null
}

# export 供 xargs 启动的子 bash 进程调用 push_repo 函数
export -f push_repo
export NEW_GITLAB
export NEW_TOKEN

find . -type d -name "*.git" | xargs -n 1 -P $CONCURRENCY bash -c '
  push_repo "$0"
'
