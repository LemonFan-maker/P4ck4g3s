#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"

ARIA2_REPO="https://github.com/aria2/aria2.git"
ARIA2_VER="latest"
ARIA2_TAR="aria2-1.37.0.tar.xz"
ARIA2_URL="https://github.com/aria2/aria2/releases/download/release-1.37.0/${ARIA2_TAR}"
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

log_info ">>> 开始从GitHub浅克隆最新代码并构建aria2(master)..."
if ! git_clone_latest "$ARIA2_REPO" "$SRC_DIR" "master" 2>/dev/null; then
    log_info "Git克隆受限,自动回退至官方发布镜像源..."
    download_tarball "$ARIA2_URL" "$ARIA2_TAR"
    rm -rf "$SRC_DIR"
    mkdir -p "$SRC_DIR"
    tar -xf "$DOWNLOADS_DIR/$ARIA2_TAR" -C "$BUILD_DIR"
    if [[ -d "$BUILD_DIR/aria2-1.37.0" ]]; then
        mv "$BUILD_DIR/aria2-1.37.0"/* "$SRC_DIR/" 2>/dev/null || true
    fi
fi
apply_patches "aria2" "$SRC_DIR"

cd "$SRC_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/etc/aria2"

if [[ ! -f configure ]]; then
    log_info "正在生成configure脚本(autoreconf -fi)..."
    autoreconf -fi 2>/dev/null || true
fi

if [[ ! -f configure ]]; then
    log_info "Git源码树缺少预构建configure,自动加载官方发布镜像包..."
    download_tarball "$ARIA2_URL" "$ARIA2_TAR"
    rm -rf "$SRC_DIR"
    mkdir -p "$SRC_DIR"
    tar -xf "$DOWNLOADS_DIR/$ARIA2_TAR" --strip-components=1 -C "$SRC_DIR"
    apply_patches "aria2" "$SRC_DIR"
    cd "$SRC_DIR"
fi

CURRENT_VER=$(sed -n "s/^PACKAGE_VERSION='\([^']*\)'.*/\1/p" configure 2>/dev/null | head -1 || true)
if [[ -z "$CURRENT_VER" ]]; then
    log_error "无法从configure解析aria2的PACKAGE_VERSION,拒绝打包"
    exit 1
fi
CURRENT_VER="$(git_pkgver "$SRC_DIR" "$CURRENT_VER")"

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
    "极速多协议多线程命令行与RPC下载实用工具(aria2c,支持HTTP/HTTPS/FTP/断点续传)" \
    "https://aria2.github.io/" \
    "GPL-2.0-or-later" \
    "base-layout" "ca-certificates"

log_success "aria2构建与打包完成!"
