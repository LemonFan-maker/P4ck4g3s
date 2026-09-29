#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

STAGING_DIR="$1"
PKG_NAME="$2"
PKG_VER="$3"
PKG_REL="$4"
PKG_DESC="$5"
PKG_URL="$6"
PKG_LICENSE="$7"
shift 7 || true
PKG_DEPENDS=("$@")

if [[ -z "$STAGING_DIR" || -z "$PKG_NAME" || -z "$PKG_VER" ]]; then
    echo "[-] 用法:$0 <staging_dir> <pkgname> <pkgver> <pkgrel> <pkgdesc> <url> <license> [depends...]"
    exit 1
fi

if ! [[ "$PKG_VER" =~ ^[0-9A-Za-z][0-9A-Za-z.+_]*$ ]]; then
    echo -e "\033[1;31m[-] 非法pkgver:'${PKG_VER}'\033[0m"
    echo -e "\033[1;31m[-] pkgver只允许数字/字母/点/加号/下划线,且不得以非数字开头\033[0m"
    echo -e "\033[1;31m[-] 不得含连字符:-DEV / -rc / -git之类后缀会让libalpm解析失败\033[0m"
    exit 1
fi
if ! [[ "$PKG_REL" =~ ^[0-9]+$ ]]; then
    echo -e "\033[1;31m[-] 非法pkgrel:'${PKG_REL}'(只允许纯数字)\033[0m"
    exit 1
fi

OUTPUT_REPO="$REPO_ROOT/output/repo"
mkdir -p "$OUTPUT_REPO"

echo -e "\033[1;34m[*] 正在封装${PKG_NAME}-${PKG_VER}-${PKG_REL}为.pkg.tar.zst归档...\033[0m"

if [[ -n "$STRIP" ]] && command -v "$STRIP" >/dev/null 2>&1; then
    find "$STAGING_DIR" -type f -name "*.so*" -exec "$STRIP" --strip-unneeded {} \; 2>/dev/null || true
    if [[ -d "$STAGING_DIR/bin" ]]; then
        find "$STAGING_DIR/bin" -type f -exec "$STRIP" --strip-unneeded {} \; 2>/dev/null || true
    fi
fi

if command -v patchelf >/dev/null 2>&1; then
    find "$STAGING_DIR" -type f | while IFS= read -r f; do
        if file "$f" 2>/dev/null | grep -q "ELF"; then
            patchelf --set-rpath '$ORIGIN/../lib64' "$f" 2>/dev/null || true
        fi
    done
fi

ELF_DEPS_RAW=""
if ! ELF_DEPS_RAW="$("$SCRIPT_DIR/elfdeps.py" resolve "$OUTPUT_REPO" "$STAGING_DIR" "$PKG_NAME")"; then
    echo -e "\033[1;31m[-] ${PKG_NAME}的ELF依赖无法求解,拒绝封装\033[0m"
    exit 1
fi
mapfile -t ELF_DEPS < <(printf '%s' "$ELF_DEPS_RAW" | grep -v '^$')

if [[ ${#ELF_DEPS[@]} -gt 0 ]]; then
    echo -e "\033[1;34m[*] 由DT_NEEDED推导出的库依赖:${ELF_DEPS[*]}\033[0m"
else
    echo -e "\033[1;34m[*] 本包无DT_NEEDED库依赖(纯数据或元包)\033[0m"
fi

INSTALLED_SIZE=$(du -sb "$STAGING_DIR" | cut -f1)

cat <<EOF > "$STAGING_DIR/.PKGINFO"
pkgname = ${PKG_NAME}
pkgbase = ${PKG_NAME}
pkgver = ${PKG_VER}-${PKG_REL}
pkgdesc = ${PKG_DESC}
url = ${PKG_URL}
builddate = $(date +%s)
packager = 0vl0ad3r Packager <packages@0vl0ad3r.org>
size = ${INSTALLED_SIZE}
arch = aarch64
license = ${PKG_LICENSE}
EOF

mapfile -t ALL_DEPS < <(printf '%s\n' "${ELF_DEPS[@]}" "${PKG_DEPENDS[@]}" \
    | grep -v '^$' | LC_ALL=C sort -u)

for dep in "${ALL_DEPS[@]}"; do
    echo "depend = $dep" >> "$STAGING_DIR/.PKGINFO"
done

cat <<EOF > "$STAGING_DIR/.BUILDINFO"
format = 2
pkgname = ${PKG_NAME}
pkgver = ${PKG_VER}-${PKG_REL}
pkgarch = aarch64
pkgbuild_sha256sum = none
builddate = $(date +%s)
buildenv = bionic-api33-ndk
EOF

PKG_FILE="${PKG_NAME}-${PKG_VER}-${PKG_REL}-aarch64.pkg.tar.zst"
PKG_PATH="$OUTPUT_REPO/$PKG_FILE"
rm -f "$PKG_PATH"

cd "$STAGING_DIR"
find . -mindepth 1 -printf '%P\n' | bsdtar -cf - -n --format pax -T - | zstd -19 -f -T"$(nproc)" -o "$PKG_PATH"
echo -e "\033[1;32m[+] 软件包封装成功:${PKG_PATH}\033[0m"

stale=0
for old in "$OUTPUT_REPO/$PKG_NAME-"*.pkg.tar.zst; do
    [[ -e "$old" ]] || continue
    if [[ "$old" != "$PKG_PATH" ]]; then
        rm -f "$old"
        stale=$((stale + 1))
    fi
done
if [[ $stale -gt 0 ]]; then
    echo -e "\033[1;33m[*] 已清理本包的${stale}个历史版本(源里同名包只应有一个)\033[0m"
fi
echo -e "\033[1;32m大小:$(du -h "$PKG_PATH" | cut -f1) | SHA256:$(sha256sum "$PKG_PATH" | cut -d' ' -f1)\033[0m"
