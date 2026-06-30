#!/usr/bin/env bash
#
# 步骤 6: 输出迁移结果汇总
#
# 统计步骤 5 产生的 success.log / fail.log 行数，打印成功与失败数量。
# 建议在步骤 5 完成后执行；若未执行过步骤 5，计数为 0。
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

echo "======================"
echo "MIGRATION DONE"
echo "Success: $(wc -l < success.log 2>/dev/null || echo 0)"
echo "Failed : $(wc -l < fail.log 2>/dev/null || echo 0)"
echo "======================"
