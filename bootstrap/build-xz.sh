#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/../scripts/manifest.sh"

SRC_DIR="$BUILD_DIR/xz"

log_info ">>> 开始构建xz(清单钉住$(manifest_ref xz))..."
fetch_source xz "$SRC_DIR"
apply_patches "xz" "$SRC_DIR"

cd "$SRC_DIR"
cmake -B build -S . \
    -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DXZ_MICROLZMA=OFF \
    -DXZ_LZIP_DECODER=OFF

cmake --build build --parallel "$(nproc)"
cmake --install build

if [[ -d "$SYSROOT/lib" ]]; then
    mkdir -p "$SYSROOT/lib64"
    cp -P "$SYSROOT/lib"/liblzma* "$SYSROOT/lib64/" 2>/dev/null || true
fi

log_success "xz构建安装完成!"
