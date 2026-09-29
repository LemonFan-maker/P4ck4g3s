#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

CURL_REPO="https://github.com/curl/curl.git"
CURL_REF="master"
SRC_DIR="$BUILD_DIR/curl"

log_info ">>> 开始从GitHub获取并构建curl(${CURL_REF})..."
git_clone_latest "$CURL_REPO" "$SRC_DIR" "$CURL_REF"
apply_patches "curl" "$SRC_DIR"

cd "$SRC_DIR"
cmake -B build -S . \
    -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_STATIC_LIBS=ON \
    -DCURL_USE_OPENSSL=ON \
    -DCURL_ZSTD=ON \
    -DCURL_ZLIB=ON \
    -DCURL_USE_LIBPSL=OFF \
    -DCURL_USE_LIBSSH2=OFF \
    -DCURL_USE_GSSAPI=OFF \
    -DENABLE_ARES=OFF \
    -DENABLE_MANUAL=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_CURL_EXE=ON \
    -DCURL_CA_PATH="/system/0vl0ad3r/etc/ssl/certs" \
    -DCURL_CA_BUNDLE="/system/0vl0ad3r/etc/ssl/cert.pem"

cmake --build build --parallel "$(nproc)"
cmake --install build

if [[ -d "$SYSROOT/lib" ]]; then
    mkdir -p "$SYSROOT/lib64"
    cp -P "$SYSROOT/lib"/libcurl* "$SYSROOT/lib64/" 2>/dev/null || true
fi

log_success "curl构建安装完成!"
