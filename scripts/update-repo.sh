#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPO_DIR="$REPO_ROOT/output/repo"
DB_NAME="0vl0ad3r"

if [[ ! -d "$REPO_DIR" ]]; then
    echo "[-] 错误:仓库目录不存在:$REPO_DIR"
    exit 1
fi

cd "$REPO_DIR"

PKG_COUNT=$(ls -1 *.pkg.tar.zst 2>/dev/null | wc -l || true)
if [[ "$PKG_COUNT" -eq 0 ]]; then
    echo "[-] 提示:未在$REPO_DIR中发现任何软件包文件"
    exit 0
fi

echo -e "\033[1;34m[*] 发现${PKG_COUNT}个软件包,正在更新${DB_NAME}.db数据库...\033[0m"

repo-add --prevent-downgrade "${DB_NAME}.db.tar.zst" *.pkg.tar.zst

ln -sf "${DB_NAME}.db.tar.zst" "${DB_NAME}.db" 2>/dev/null || true
ln -sf "${DB_NAME}.files.tar.zst" "${DB_NAME}.files" 2>/dev/null || true

"$SCRIPT_DIR/gen-index.py" "${DB_NAME}.db.tar.zst" "index.json"
ls -lh "${DB_NAME}".*
