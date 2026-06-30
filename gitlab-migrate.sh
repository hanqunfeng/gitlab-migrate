#!/usr/bin/env bash
#
# GitLab 迁移工具 — 统一入口
#
# 根据命令行参数调度 scripts/ 目录下的各步骤脚本，支持单独执行或组合执行。
# 不带参数时仅显示帮助信息，不会自动执行任何步骤。
#
# 用法:
#   ./gitlab-migrate.sh all       # 执行全部步骤 (1-6)
#   ./gitlab-migrate.sh 1 2 3     # 执行指定步骤
#   ./gitlab-migrate.sh --help    # 显示帮助
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

辅助工具请使用 ./gitlab-util.sh（删除误创建的 Group/Project 等）

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
