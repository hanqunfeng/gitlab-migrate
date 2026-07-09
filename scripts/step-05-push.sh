#!/usr/bin/env bash
#
# 步骤 5：并行 push（mirror）到新 GitLab
#
# 目标：
# - 遍历步骤 4 生成的本地裸仓库目录 `{namespace}/{project}.git/`
# - 对每个裸仓库执行 `git push --mirror` 推送到新实例同路径项目
#
# 输入目录（位于 WORKDIR，默认 `./gitlab-migration`）：
# - {namespace}/{project}.git/
#
# 输出文件（位于 WORKDIR）：
# - success.log：push 成功的项目列表（每行：`[OK] namespace/project`）
# - fail.log：push 失败的项目列表（每行：`[FAIL] namespace/project`）
#
# 依赖：
# - git、find、xargs
#
# 并发控制：
# - 使用 `xargs -P $CONCURRENCY` 并行 push
# - 并发数由 `scripts/config.sh` 的 `CONCURRENCY` 控制（默认 6）
#
# 认证方式：
# - 使用 `NEW_TOKEN` 通过 GitLab 的 HTTP Basic 方式鉴权
# - 用户名固定用 `oauth2`（GitLab 对 PAT 的常见占位用户名），密码为 token
# - 脚本不会在日志中输出 token（但请注意不要在命令行历史中直接回显 token）
#
# 行为与重跑语义：
# - 本步骤不会自动跳过已成功项目；重复执行会再次对所有裸仓库尝试 push
# - 建议结合 success.log / fail.log 做复跑策略（例如仅重试失败项）
#
# 注意：
# - push --mirror 会覆盖目标仓库 refs（分支/标签等）；目标项目应为空或确认允许覆盖
# - 并发过高可能导致新实例限流、HTTP 502/503、或网络/IO 饱和；可适当降低 CONCURRENCY
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

  # 注意：这里每个 push 任务都会进入对应裸仓库目录执行 git push --mirror。
  # 因为 xargs 并行运行在“独立的子 bash 进程”中，所以 cd 不会影响主进程。
  cd "$dir"

  # 使用 NEW_TOKEN 认证 push；日志中不暴露 token
  git -c "credential.helper=!f() { echo \"username=oauth2\"; echo \"password=${NEW_TOKEN}\"; }; f" \
    push --mirror "$url" \
    && echo "[OK] $group/$project" >> ../../success.log \
    || echo "[FAIL] $group/$project" >> ../../fail.log

  cd - > /dev/null
}

# export 供 xargs 启动的子 bash 进程调用 push_repo 函数
# 这是 Bash 的一个“非直观点”：xargs 启动新 shell 时不会继承当前 shell 的函数定义，
# 必须 export -f 才能在子进程里调用 push_repo。
export -f push_repo
export NEW_GITLAB
export NEW_TOKEN

find . -type d -name "*.git" | xargs -n 1 -P $CONCURRENCY bash -c '
  push_repo "$0"
'
