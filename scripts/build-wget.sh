#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

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

log_info ">>> 开始构建GNU Wget(清单钉住$(manifest_require_version wget))..."

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/etc"
fetch_source wget "$SRC_DIR"
apply_patches "wget" "$SRC_DIR"

cd "$SRC_DIR"

CURRENT_VER="$(manifest_require_version wget)"

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
    "$(manifest_desc wget)" \
    "https://www.gnu.org/software/wget/" \
    "GPL-3.0-or-later" \
    "base-layout" "ca-certificates"

log_success "wget构建与打包完成!"
