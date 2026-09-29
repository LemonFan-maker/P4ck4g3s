#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEST="${1:?用法:publish-repo.sh <发布目录> [tag]}"
TAG="${2:-}"
CUSTOM_DOMAIN="${OVL0AD3R_DOMAIN:-}"

REPO_SRC="$REPO_ROOT/output/repo"

if [[ ! -f "$REPO_SRC/index.json" ]]; then
    echo "[-] 错误:$REPO_SRC/index.json不存在,请先执行./scripts/update-repo.sh" >&2
    exit 1
fi

PKG_COUNT=$(find "$REPO_SRC" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)
if [[ "$PKG_COUNT" -eq 0 ]]; then
    echo "[-] 错误:未找到任何软件包文件" >&2
    exit 1
fi

# 引导种子包不由 pacman 拉取(客户端从 APK asset 读取, 这里是给手动/CLI 引导
# 留的稳定下载地址), 所以可以放进子目录。路径与客户端
# app/src/main/assets/bootstrap/ 保持一致, 维护时只需记一套。
BOOTSTRAP_SEED="$REPO_ROOT/output/bootstrap/0vl0ad3r-bootstrap-aarch64.tar.zst"
if [[ ! -f "$BOOTSTRAP_SEED" ]]; then
    echo "[-] 错误:引导种子包不存在($BOOTSTRAP_SEED)" >&2
    echo "    请确认已执行 ./scripts/build-all-tools.sh 或 ./bootstrap/build-all.sh" >&2
    exit 1
fi

echo -e "\033[1;34m[*] 正在准备gh-pages发布目录:$DEST(${PKG_COUNT}个包)\033[0m"

rm -rf "$DEST"
mkdir -p "$DEST"

cp -a "$REPO_SRC"/*.pkg.tar.zst "$DEST/"
cp -a "$REPO_SRC/index.json" "$DEST/"
cp -a "$REPO_SRC/0vl0ad3r.db.tar.zst" "$DEST/"
cp -a "$REPO_SRC/0vl0ad3r.files.tar.zst" "$DEST/"
mkdir -p "$DEST/bootstrap"
cp -a "$BOOTSTRAP_SEED" "$DEST/bootstrap/"

ln -sf 0vl0ad3r.db.tar.zst "$DEST/0vl0ad3r.db"
ln -sf 0vl0ad3r.files.tar.zst "$DEST/0vl0ad3r.files"

if [[ -n "$CUSTOM_DOMAIN" ]]; then
    printf '%s\n' "$CUSTOM_DOMAIN" > "$DEST/CNAME"
    echo -e "\033[1;34m[*] 已写入CNAME:$CUSTOM_DOMAIN\033[0m"
else
    echo -e "\033[1;33m[-] 未设置OVL0AD3R_DOMAIN,不生成CNAME(gh-pages将使用默认*.github.io地址)\033[0m"
fi

if [[ -n "$TAG" ]]; then
    printf '%s\n' "$TAG" > "$DEST/latest"
fi

echo -e "\033[1;32m[+] 发布目录就绪($(find "$DEST" -maxdepth 1 \( -type f -o -type l \) | wc -l)个顶层条目)\033[0m"
