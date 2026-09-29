#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

OPENSSL_REPO="https://github.com/openssl/openssl.git"
OPENSSL_BRANCH="openssl-3.4"
SRC_DIR="$BUILD_DIR/openssl"

log_info ">>> 开始从GitHub获取并构建OpenSSL(${OPENSSL_BRANCH})..."
git_clone_latest "$OPENSSL_REPO" "$SRC_DIR" "$OPENSSL_BRANCH"
apply_patches "openssl" "$SRC_DIR"

cd "$SRC_DIR"
export ANDROID_NDK_ROOT="$ANDROID_NDK_ROOT"
export PATH="$NDK_TOOLCHAIN/bin:$PATH"

./Configure android-arm64 \
    -D__ANDROID_API__="$ANDROID_API" \
    --prefix="$SYSROOT" \
    --openssldir="$SYSROOT/etc/ssl" \
    shared \
    no-tests \
    no-unit-test \
    -Wl,-rpath,'\$$ORIGIN/../lib64' \
    -Wl,--enable-new-dtags

make -j"$(nproc)"
make install_sw

if [[ -d "$SYSROOT/lib" ]]; then
    mkdir -p "$SYSROOT/lib64"
    cp -P "$SYSROOT/lib"/libssl* "$SYSROOT/lib64/" 2>/dev/null || true
    cp -P "$SYSROOT/lib"/libcrypto* "$SYSROOT/lib64/" 2>/dev/null || true
fi

log_success "OpenSSL构建安装完成!"
