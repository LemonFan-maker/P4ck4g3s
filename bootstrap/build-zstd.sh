#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

ZSTD_REPO="https://github.com/facebook/zstd.git"
ZSTD_TAG="v1.5.6"
SRC_DIR="$BUILD_DIR/zstd"

log_info ">>> 开始从GitHub获取并构建zstd(${ZSTD_TAG})..."
git_clone_latest "$ZSTD_REPO" "$SRC_DIR" "$ZSTD_TAG"
apply_patches "zstd" "$SRC_DIR"

cd "$SRC_DIR"
cmake -B build -S build/cmake \
    -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DZSTD_BUILD_PROGRAMS=ON \
    -DZSTD_BUILD_SHARED=ON \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_LEGACY_SUPPORT=OFF

cmake --build build --parallel "$(nproc)"
cmake --install build

if [[ -d "$SYSROOT/lib" ]]; then
    mkdir -p "$SYSROOT/lib64"
    cp -P "$SYSROOT/lib"/libzstd* "$SYSROOT/lib64/" 2>/dev/null || true
fi

log_success "zstd构建安装完成!"
