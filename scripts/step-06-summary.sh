#!/usr/bin/env bash
#
# 步骤 6：输出迁移结果汇总（success / fail 统计）
#
# 目标：
# - 汇总步骤 5 写入的 success.log / fail.log
# - 打印成功与失败数量，作为迁移收尾的快速检查
#
# 输入文件（位于 WORKDIR，默认 `./gitlab-migration`）：
# - success.log：push 成功记录（由步骤 5 生成）
# - fail.log：push 失败记录（由步骤 5 生成）
#
# 输出：
# - 标准输出打印统计结果（不会写入新的文件）
#
# 行为与重跑语义：
# - 若 success.log / fail.log 不存在，则对应计数为 0
# - 可随时重复执行，不修改任何迁移数据（纯只读统计）
#
# 常见排障建议：
# - fail_count > 0 时：查看 fail.log 中失败项目路径，并结合新实例/网络/权限排查后重试 push
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

success_count=0
fail_count=0
[[ -f success.log ]] && success_count=$(wc -l < success.log | tr -d ' ')
[[ -f fail.log ]] && fail_count=$(wc -l < fail.log | tr -d ' ')

echo "======================"
echo "MIGRATION DONE"
echo "Success: $success_count"
echo "Failed : $fail_count"
echo "======================"
