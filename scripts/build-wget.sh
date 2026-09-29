#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"

WGET_VER="1.24.5"
WGET_TAR="wget-${WGET_VER}.tar.gz"
WGET_URL="https://ftp.gnu.org/gnu/wget/${WGET_TAR}"
WGET_URL_FALLBACK="https://mirrors.kernel.org/gnu/wget/${WGET_TAR}"
SRC_DIR="$BUILD_DIR/wget"
STAGING_DIR="$BUILD_DIR/staging_wget"

if [[ ! -f "$SYSROOT/lib64/libz.so" && ! -f "$SYSROOT/lib/libz.so" ]]; then
    log_info "检测到依赖库zlib缺失,正在前置构建zlib..."
    "$REPO_ROOT/bootstrap/build-zlib.sh"
fi
if [[ ! -f "$SYSROOT/lib64/libssl.so" || ! -f "$SYSROOT/lib64/libcrypto.so" ]]; then
    log_info "检测到依赖库openssl缺失,正在前置构建openssl..."
    "$REPO_ROOT/bootstrap/build-openssl.sh"
fi

log_info ">>> 获取并构建GNU Wget(${WGET_VER})..."

if [[ ! -f "$DOWNLOADS_DIR/$WGET_TAR" ]]; then
    download_tarball "$WGET_URL" "$WGET_TAR" || download_tarball "$WGET_URL_FALLBACK" "$WGET_TAR"
fi

rm -rf "$SRC_DIR" "$STAGING_DIR"
mkdir -p "$SRC_DIR" "$STAGING_DIR/bin" "$STAGING_DIR/etc"
tar -xzf "$DOWNLOADS_DIR/$WGET_TAR" --strip-components=1 -C "$SRC_DIR"
apply_patches "wget" "$SRC_DIR"

cd "$SRC_DIR"

CURRENT_VER=$(grep -m1 "PACKAGE_VERSION=" configure 2>/dev/null | cut -d"'" -f2 || echo "1.24.5")
[[ -z "$CURRENT_VER" ]] && CURRENT_VER="1.24.5"

export CFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I$SYSROOT/include"
export LDFLAGS="-L$SYSROOT/lib -L$SYSROOT/lib64 -lssl -lcrypto -lz -Wl,-rpath,'\$ORIGIN/../lib64' -Wl,--enable-new-dtags"
export OPENSSL_CFLAGS="-I$SYSROOT/include"
export OPENSSL_LIBS="-L$SYSROOT/lib64 -lssl -lcrypto"

./configure \
    --host="$TARGET_TRIPLE" \
    --prefix="$TARGET_PREFIX" \
    --sysconfdir="$TARGET_PREFIX/etc" \
    --mandir="$TARGET_PREFIX/share/man" \
    --with-ssl=openssl \
    --with-libssl-prefix="$SYSROOT" \
    --disable-nls \
    --disable-rpath \
    --disable-pcre \
    --disable-pcre2 \
    --disable-iri \
    --without-libpsl \
    --without-libuuid \
    --without-included-regex

make -j"$(nproc)"
rm -rf "$BUILD_DIR/dest_wget"
make install DESTDIR="$BUILD_DIR/dest_wget"

cp -a "$BUILD_DIR/dest_wget/system/0vl0ad3r"/* "$SYSROOT/" 2>/dev/null || true
cp -a "$BUILD_DIR/dest_wget/system/0vl0ad3r"/* "$STAGING_DIR/" 2>/dev/null || true

rm -f "$STAGING_DIR/share/info/dir"

cat <<'EOF' > "$STAGING_DIR/etc/wgetrc"
ca_certificate = /system/0vl0ad3r/etc/ssl/cert.pem
check_certificate = on
tries = 3
timeout = 30
continue = on
EOF

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "wget" \
    "$CURRENT_VER" \
    "1" \
    "经典非交互式命令行网络下载器(GNU Wget,支持HTTPS/断点续传/OpenSSL)" \
    "https://www.gnu.org/software/wget/" \
    "GPL-3.0-or-later" \
    "base-layout" "ca-certificates"

log_success "wget构建与打包完成!"
