#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/../scripts/manifest.sh"

SRC_DIR="$BUILD_DIR/openssl"

log_info ">>> 开始构建OpenSSL(清单钉住$(manifest_ref openssl))..."
fetch_source openssl "$SRC_DIR"
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
