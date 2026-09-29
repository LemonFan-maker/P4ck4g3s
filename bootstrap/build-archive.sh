#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

ARCHIVE_REPO="https://github.com/libarchive/libarchive.git"
ARCHIVE_TAG="v3.8.9"
SRC_DIR="$BUILD_DIR/libarchive"

log_info ">>> 开始从GitHub获取并构建libarchive(${ARCHIVE_TAG})..."
git_clone_latest "$ARCHIVE_REPO" "$SRC_DIR" "$ARCHIVE_TAG"
apply_patches "libarchive" "$SRC_DIR"

cd "$SRC_DIR"
cmake -B build -S . \
    -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DENABLE_ZLIB=ON \
    -DENABLE_ZSTD=ON \
    -DENABLE_LZMA=ON \
    -DENABLE_OPENSSL=ON \
    -DENABLE_TEST=OFF \
    -DENABLE_CAT=ON \
    -DENABLE_TAR=ON \
    -DENABLE_CPIO=OFF \
    -DENABLE_XATTR=OFF \
    -DENABLE_ACL=OFF

cmake --build build --parallel "$(nproc)"
cmake --install build

if [[ -d "$SYSROOT/lib" ]]; then
    mkdir -p "$SYSROOT/lib64"
    cp -P "$SYSROOT/lib"/libarchive* "$SYSROOT/lib64/" 2>/dev/null || true
fi

log_success "libarchive构建安装完成!"
