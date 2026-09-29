#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/../scripts/manifest.sh"

SRC_DIR="$BUILD_DIR/zlib"

log_info ">>> 开始构建zlib(清单钉住$(manifest_ref zlib))..."
fetch_source zlib "$SRC_DIR"
apply_patches "zlib" "$SRC_DIR"

cd "$SRC_DIR"
cmake -B build -S . \
    -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON

cmake --build build --parallel "$(nproc)"
cmake --install build

if [[ -d "$SYSROOT/lib" ]]; then
    mkdir -p "$SYSROOT/lib64"
    cp -P "$SYSROOT/lib"/libz* "$SYSROOT/lib64/" 2>/dev/null || true
fi

mkdir -p "$SYSROOT/lib/pkgconfig" "$SYSROOT/lib64/pkgconfig"
if [[ -f "$SYSROOT/share/pkgconfig/zlib.pc" ]]; then
    cp -f "$SYSROOT/share/pkgconfig/zlib.pc" "$SYSROOT/lib/pkgconfig/"
    cp -f "$SYSROOT/share/pkgconfig/zlib.pc" "$SYSROOT/lib64/pkgconfig/"
fi

log_success "zlib构建安装完成!"
