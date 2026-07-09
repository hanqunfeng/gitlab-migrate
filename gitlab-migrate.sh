#!/usr/bin/env bash
#
# GitLab 仓库迁移工具 — 统一入口（步骤 1–6）
#
# 本脚本本身不直接访问 GitLab API / 不直接执行 git clone/push，而是根据命令行参数
# 调度 `scripts/` 目录下的各步骤脚本：
#
#   1) 拉取项目列表（生成 repos.txt）
#   2) 在新 GitLab 创建 Group（仅 group namespace）
#   3) 在新 GitLab 创建 Project（group / user namespace）
#   4) 从旧 GitLab mirror clone 到本地裸仓库
#   5) 并行 mirror push 到新 GitLab
#   6) 输出成功/失败汇总
#
# 设计原则：
# - 入口脚本“只负责编排”，每一步的输入输出文件都在工作目录（WORKDIR）内，便于断点续跑。
# - 不带参数时仅显示帮助信息，避免误触发全量迁移。
#
# 前置条件：
# - 已从 `scripts/config.example.sh` 复制并编辑 `scripts/config.sh`
# - 本机已安装 bash 4+、curl、jq、git（步骤 5 还需要 find/xargs）
# - `OLD_TOKEN` / `NEW_TOKEN` 具备脚本所需 API 与仓库权限（详见 README）
#
# 工作目录（默认 `./gitlab-migration`）产物：
# - repos.txt                 步骤 1 生成：namespace_kind|namespace|project|http_url_to_repo
# - groups_created.txt        步骤 2 生成：本次新建的 group path
# - projects_created.txt      步骤 3 生成：本次新建的 project path
# - projects_skipped_user.txt 步骤 3 生成：因目标实例缺用户而跳过的个人项目
# - {namespace}/{project}.git 步骤 4 生成：mirror 裸仓库目录
# - success.log / fail.log    步骤 5 生成：push 成功/失败清单
#
# 用法：
#   ./gitlab-migrate.sh all       # 执行全部步骤 (1-6)
#   ./gitlab-migrate.sh 1 2 3     # 执行指定步骤（可任意组合）
#   ./gitlab-migrate.sh 4 5 6     # 基于已有 repos.txt 与本地镜像续跑后半段
#   ./gitlab-migrate.sh --help    # 显示帮助
#
# 重跑语义（幂等/断点）：
# - 步骤 2/3：若目标资源已存在则跳过；重复执行安全
# - 步骤 4：若本地裸仓库目录已存在则跳过；重复执行安全
# - 步骤 5：不会自动跳过已成功项，依赖 success.log/fail.log 进行人工复跑策略
# - 步骤 1：会清空并重新生成 repos.txt（以旧实例当前项目列表为准）
#
# 注意：
# - 本工具聚焦“代码仓库 + 用户/成员权限”，不迁移 Issue/MR/Wiki 等元数据
# - 请勿把包含 token 的 `scripts/config.sh` 提交到仓库（已在 .gitignore 中忽略）
#

set -euo pipefail

# 入口脚本所在目录，用于定位 scripts/ 子目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# 打印帮助信息
usage() {
  cat <<EOF
Usage: $(basename "$0") [all|1|2|3|4|5|6] ...

GitLab 迁移工具 — 按步骤执行迁移流程。

步骤说明:
  1  从旧 GitLab 拉取所有项目列表
  2  在新 GitLab 创建 Group
  3  在新 GitLab 创建 Project
  4  Mirror clone 仓库
  5  并行 push 到新 GitLab
  6  输出迁移结果汇总

示例:
  $(basename "$0") all       # 执行全部步骤
  $(basename "$0") 1         # 仅执行步骤 1
  $(basename "$0") 1 2 3     # 执行步骤 1、2、3
  $(basename "$0") 4 5 6     # 执行步骤 4、5、6
EOF
}

# 根据步骤编号执行对应的子脚本
run_step() {
  local step=$1
  local script=""

  case "$step" in
    1) script="step-01-fetch-projects.sh" ;;
    2) script="step-02-create-groups.sh" ;;
    3) script="step-03-create-projects.sh" ;;
    4) script="step-04-mirror-clone.sh" ;;
    5) script="step-05-push.sh" ;;
    6) script="step-06-summary.sh" ;;
    *)
      echo "[ERROR] 未知步骤: $step"
      usage
      exit 1
      ;;
  esac

  echo ""
  echo "========================================"
  echo " 开始执行步骤 $step"
  echo "========================================"
  bash "$SCRIPTS_DIR/$script"
}

main() {
  local steps=()

  # 无参数时仅显示帮助，避免误触发全量迁移
  if [ $# -eq 0 ]; then
    usage
    exit 0
  else
    for arg in "$@"; do
      case "$arg" in
        -h|--help)
          usage
          exit 0
          ;;
        all)
          # all 会覆盖为完整流程；若与其他数字混用，以最后一次 all 为准
          steps=(1 2 3 4 5 6)
          ;;
        [1-6])
          steps+=("$arg")
          ;;
        *)
          echo "[ERROR] 未知参数: $arg"
          usage
          exit 1
          ;;
      esac
    done
  fi

  for step in "${steps[@]}"; do
    run_step "$step"
  done
}

main "$@"
