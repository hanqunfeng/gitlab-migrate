#!/usr/bin/env bash
#
# 辅助工具: 查看本次迁移创建的资源记录
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
init_workdir

echo "=== groups_created.txt ==="
if [[ -f groups_created.txt ]]; then
  cat groups_created.txt
else
  echo "(空 — 尚未执行步骤 2 或未创建新 Group)"
fi

echo ""
echo "=== projects_created.txt ==="
if [[ -f projects_created.txt ]]; then
  cat projects_created.txt
else
  echo "(空 — 尚未执行步骤 3 或未创建新 Project)"
fi
