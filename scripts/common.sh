#!/usr/bin/env bash
#
# GitLab 迁移 — 共享工具函数
#
# 所有步骤脚本 source 本文件，并通过 load_config 加载用户配置。
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载 scripts/config.sh；若不存在则提示从 config.example.sh 复制
load_config() {
  local config_file="$SCRIPT_DIR/config.sh"

  if [[ ! -f "$config_file" ]]; then
    echo "[ERROR] 未找到 scripts/config.sh"
    echo ""
    echo "首次使用请执行:"
    echo "  cp scripts/config.example.sh scripts/config.sh"
    echo "  # 编辑 scripts/config.sh，填入 GitLab 地址和 Token"
    exit 1
  fi

  # shellcheck source=config.sh
  source "$config_file"
}

# 创建并进入工作目录；所有步骤的数据文件都写在此目录下
init_workdir() {
  mkdir -p "$PROJECT_ROOT/$WORKDIR"
  cd "$PROJECT_ROOT/$WORKDIR"
}

# repos.txt 最后一行若无换行符，bash 的 while read 会跳过该行。
# 在读取 repos.txt 之前调用，确保每一行都能被正确处理。
fix_repos_txt() {
  local f="repos.txt"
  [[ -s "$f" ]] || return 0
  [[ $(tail -c1 "$f") == $'\n' ]] || echo >> "$f"
}

# URL 编码，用于 GitLab API 路径参数（如 group/project 中的斜杠）
urlencode() {
  jq -nr --arg v "$1" '$v|@uri'
}
