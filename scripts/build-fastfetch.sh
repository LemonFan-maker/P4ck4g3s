#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

SRC_DIR="$BUILD_DIR/fastfetch"
CMAKE_BUILD_DIR="$BUILD_DIR/fastfetch-build"
STAGING_DIR="$BUILD_DIR/staging_fastfetch"
DEST_DIR="$BUILD_DIR/dest_fastfetch"
# pkgrel 2: avoid Android's private libmedia/libandroidicu linker namespace.
FASTFETCH_PKGREL="2"

if [[ ! -f "$SYSROOT/lib64/libz.so" && ! -f "$SYSROOT/lib/libz.so" ]]; then
    log_info "检测到依赖库zlib缺失,正在前置构建zlib..."
    "$REPO_ROOT/bootstrap/build-zlib.sh"
fi

log_info ">>> 开始构建fastfetch(清单钉住$(manifest_require_version fastfetch))..."
fetch_source fastfetch "$SRC_DIR"
apply_patches "fastfetch" "$SRC_DIR"

cd "$SRC_DIR"

CURRENT_VER="$(manifest_require_version fastfetch)"
SOURCE_VER="$(sed -n '/^project(fastfetch/,/)/s/^[[:space:]]*VERSION[[:space:]]\+\([0-9][0-9.]*\).*/\1/p' CMakeLists.txt | head -1)"
if [[ -z "$SOURCE_VER" ]]; then
    log_error "无法从CMakeLists.txt解析fastfetch版本,拒绝打包"
    exit 1
fi
if [[ "$CURRENT_VER" != "$SOURCE_VER" ]]; then
    log_error "fastfetch版本与清单不符:源码为$SOURCE_VER,清单为$CURRENT_VER"
    log_error "请运行./scripts/sync-archlinux.py刷新清单,或确认ref是否已指向新版本"
    exit 1
fi

rm -rf "$CMAKE_BUILD_DIR" "$DEST_DIR" "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cmake -S "$SRC_DIR" -B "$CMAKE_BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="$TARGET_PREFIX" \
    -DCMAKE_INSTALL_SYSCONFDIR="$TARGET_PREFIX/etc" \
    -DTARGET_DIR_ROOT="$TARGET_PREFIX" \
    -DTARGET_DIR_USR="$TARGET_PREFIX" \
    -DTARGET_DIR_ETC="$TARGET_PREFIX/etc" \
    -DTARGET_DIR_HOME="/data/local/tmp" \
    -DBUILD_FLASHFETCH=OFF \
    -DBUILD_TESTS=OFF \
    -DENABLE_IMAGE_LOGO=OFF \
    -DENABLE_VULKAN=OFF \
    -DENABLE_WAYLAND=OFF \
    -DENABLE_XCB_RANDR=OFF \
    -DENABLE_XRANDR=OFF \
    -DENABLE_DRM=OFF \
    -DENABLE_VADRM=OFF \
    -DENABLE_VAX11=OFF \
    -DENABLE_VDPAU=OFF \
    -DENABLE_GIO=OFF \
    -DENABLE_DCONF=OFF \
    -DENABLE_EET=OFF \
    -DENABLE_DBUS=OFF \
    -DENABLE_SQLITE3=OFF \
    -DENABLE_RPM=OFF \
    -DENABLE_EGL=OFF \
    -DENABLE_GLX=OFF \
    -DENABLE_OPENCL=OFF \
    -DENABLE_FREETYPE=OFF \
    -DENABLE_ELF=OFF \
    -DENABLE_LUA=OFF \
    -DENABLE_LIBZFS=OFF \
    -DENABLE_WORDEXP=OFF \
    -DENABLE_ZLIB=ON

cmake --build "$CMAKE_BUILD_DIR" --parallel "$(nproc)"

DESTDIR="$DEST_DIR" cmake --install "$CMAKE_BUILD_DIR" --prefix "$TARGET_PREFIX"

cp -a "$DEST_DIR$TARGET_PREFIX"/* "$SYSROOT/"
cp -a "$DEST_DIR$TARGET_PREFIX"/* "$STAGING_DIR/"

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "fastfetch" \
    "$CURRENT_VER" \
    "$FASTFETCH_PKGREL" \
    "$(manifest_desc fastfetch)" \
    "https://github.com/fastfetch-cli/fastfetch" \
    "MIT" \
    "base-layout" "zlib"

log_success "fastfetch构建与打包完成!"
