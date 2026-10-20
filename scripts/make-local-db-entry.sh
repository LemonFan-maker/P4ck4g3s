#!/usr/bin/env bash
set -eo pipefail

PKG_FILE="${1:?用法: make-local-db-entry.sh <pkg.tar.zst> <pacman-local-dir>}"
LOCAL_DIR="${2:?用法: make-local-db-entry.sh <pkg.tar.zst> <pacman-local-dir>}"

if [[ ! -f "$PKG_FILE" ]]; then
    echo "[-] 包不存在: $PKG_FILE" >&2
    exit 1
fi

mkdir -p "$LOCAL_DIR"

if [[ ! -f "$LOCAL_DIR/ALPM_DB_VERSION" ]]; then
    printf '9\n' > "$LOCAL_DIR/ALPM_DB_VERSION"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

bsdtar -xf "$PKG_FILE" -C "$TMP_DIR" .PKGINFO

PKGINFO="$TMP_DIR/.PKGINFO"
get_field() {
    sed -n "s/^$1 = //p" "$PKGINFO" | head -n 1
}

NAME="$(get_field pkgname)"
VERSION="$(get_field pkgver)"
BASE="$(get_field pkgbase)"
DESC="$(get_field pkgdesc)"
URL="$(get_field url)"
BUILDDATE="$(get_field builddate)"
PACKAGER="$(get_field packager)"
ISIZE="$(get_field size)"
ARCH="$(get_field arch)"

if [[ -z "$NAME" || -z "$VERSION" ]]; then
    echo "[-] 包元数据缺少 pkgname 或 pkgver: $PKG_FILE" >&2
    exit 1
fi

ENTRY="$LOCAL_DIR/$NAME-$VERSION"
rm -rf "$ENTRY"
mkdir -p "$ENTRY"

{
    printf '%%NAME%%\n%s\n\n' "$NAME"
    printf '%%VERSION%%\n%s\n\n' "$VERSION"
    [[ -n "$BASE" ]] && printf '%%BASE%%\n%s\n\n' "$BASE"
    [[ -n "$DESC" ]] && printf '%%DESC%%\n%s\n\n' "$DESC"
    [[ -n "$URL" ]] && printf '%%URL%%\n%s\n\n' "$URL"
    [[ -n "$ARCH" ]] && printf '%%ARCH%%\n%s\n\n' "$ARCH"
    [[ -n "$BUILDDATE" ]] && printf '%%BUILDDATE%%\n%s\n\n' "$BUILDDATE"
    [[ -n "$PACKAGER" ]] && printf '%%PACKAGER%%\n%s\n\n' "$PACKAGER"
    [[ -n "$ISIZE" ]] && printf '%%SIZE%%\n%s\n\n' "$ISIZE"
    # bootstrap 解压即视为安装完成; 写入当前时间, 免得 pacman -Qi 显示 1970。
    printf '%%INSTALLDATE%%\n%s\n\n' "$(date +%s)"
    # 显式安装, 避免被当成孤儿依赖自动清理。
    printf '%%REASON%%\n0\n\n'
    printf '%%VALIDATION%%\nnone\n\n'

    LICENSE_LINES="$(sed -n 's/^license = //p' "$PKGINFO")"
    if [[ -n "$LICENSE_LINES" ]]; then
        printf '%%LICENSE%%\n%s\n\n' "$LICENSE_LINES"
    fi

    DEP_LINES="$(sed -n 's/^depend = //p' "$PKGINFO")"
    if [[ -n "$DEP_LINES" ]]; then
        printf '%%DEPENDS%%\n%s\n\n' "$DEP_LINES"
    fi
} > "$ENTRY/desc"

{
    printf '%%FILES%%\n'
    bsdtar -tf "$PKG_FILE" \
        | grep -v -E '^\.?(PKGINFO|BUILDINFO|MTREE|INSTALL|Changelog)$' \
        | sed 's|^\./||'
    printf '\n'
} > "$ENTRY/files"

echo "[+] 已生成 pacman 本地库条目: $ENTRY"
