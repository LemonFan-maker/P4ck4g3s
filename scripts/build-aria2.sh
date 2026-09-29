#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

SRC_DIR="$BUILD_DIR/aria2"
STAGING_DIR="$BUILD_DIR/staging_aria2"

if [[ ! -f "$SYSROOT/lib64/libz.so" && ! -f "$SYSROOT/lib/libz.so" ]]; then
    log_info "检测到依赖库zlib缺失,执行前置编译..."
    "$REPO_ROOT/bootstrap/build-zlib.sh"
fi
if [[ ! -f "$SYSROOT/lib64/libssl.so" || ! -f "$SYSROOT/lib64/libcrypto.so" ]]; then
    log_info "检测到依赖库openssl缺失,执行前置编译..."
    "$REPO_ROOT/bootstrap/build-openssl.sh"
fi

log_info ">>> 开始构建aria2(清单钉住$(manifest_require_version aria2))..."
fetch_source aria2 "$SRC_DIR"
apply_patches "aria2" "$SRC_DIR"

cd "$SRC_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/etc/aria2"

if [[ ! -f configure ]]; then
    log_info "正在生成configure脚本(autoreconf -fi)..."
    if ! autoreconf -fi; then
        log_error "autoreconf -fi失败,aria2无法生成configure(上面是autotools的原始报错)"
        log_error "宿主需要autoconf / automake / libtool / gettext"
        exit 1
    fi
fi

if [[ ! -f configure ]]; then
    log_error "aria2源码树仍缺少configure,拒绝构建"
    log_error "aria2走git ref而非tarball,上游仓库不带configure,只能靠上面的autoreconf生成"
    exit 1
fi

CURRENT_VER="$(manifest_require_version aria2)"

export CFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I$SYSROOT/include"
export CXXFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I$SYSROOT/include"
export LDFLAGS="-L$SYSROOT/lib -L$SYSROOT/lib64 -lssl -lcrypto -lz -Wl,-rpath,'\$ORIGIN/../lib64' -Wl,--enable-new-dtags"
export OPENSSL_CFLAGS="-I$SYSROOT/include"
export OPENSSL_LIBS="-L$SYSROOT/lib64 -lssl -lcrypto"
export ZLIB_CFLAGS="-I$SYSROOT/include"
export ZLIB_LIBS="-L$SYSROOT/lib64 -lz"

./configure \
    --host="$TARGET_TRIPLE" \
    --prefix="$TARGET_PREFIX" \
    --sysconfdir="$TARGET_PREFIX/etc" \
    --mandir="$TARGET_PREFIX/share/man" \
    --with-openssl \
    --without-gnutls \
    --with-libz \
    --without-libxml2 \
    --without-expat \
    --without-sqlite3 \
    --without-libcares \
    --without-libssh2 \
    --disable-nls \
    --disable-epoll \
    --enable-shared=no \
    --enable-static=yes

make -j"$(nproc)"
rm -rf "$BUILD_DIR/dest_aria2"
make install DESTDIR="$BUILD_DIR/dest_aria2"

cp -a "$BUILD_DIR/dest_aria2/system/0vl0ad3r"/* "$SYSROOT/" 2>/dev/null || true
cp -a "$BUILD_DIR/dest_aria2/system/0vl0ad3r/bin/aria2c" "$STAGING_DIR/bin/"

cat <<'EOF' > "$STAGING_DIR/etc/aria2/aria2.conf.example"
dir=/data/local/tmp
continue=true
max-connection-per-server=16
split=16
min-split-size=1M
ca-certificate=/system/0vl0ad3r/etc/ssl/cert.pem
check-certificate=true
user-agent=0vl0ad3r/aria2c
EOF

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "aria2" \
    "$CURRENT_VER" \
    "1" \
    "$(manifest_desc aria2)" \
    "https://aria2.github.io/" \
    "GPL-2.0-or-later" \
    "base-layout" "ca-certificates"

log_success "aria2构建与打包完成!"
