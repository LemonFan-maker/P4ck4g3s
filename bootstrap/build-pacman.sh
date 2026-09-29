#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

PACMAN_REPO="https://gitlab.archlinux.org/pacman/pacman.git"
PACMAN_TAG="v7.1.0"
SRC_DIR="$BUILD_DIR/pacman"

log_info ">>> 开始从Arch Linux官方仓库获取并构建pacman(${PACMAN_TAG})..."
git_clone_latest "$PACMAN_REPO" "$SRC_DIR" "$PACMAN_TAG"
apply_patches "pacman" "$SRC_DIR"

cd "$SRC_DIR"
export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig:$SYSROOT/lib64/pkgconfig:$SYSROOT/share/pkgconfig"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"

rm -rf build
meson setup build \
    --cross-file "$MESON_CROSS_FILE" \
    --prefix="$TARGET_PREFIX" \
    --sysconfdir="$TARGET_PREFIX/etc" \
    --localstatedir="$TARGET_PREFIX/var" \
    -Droot-dir="$TARGET_PREFIX" \
    -Dpkg-ext=.pkg.tar.zst \
    -Dscriptlet-shell=/system/bin/sh \
    -Dldconfig='' \
    -Dcrypto=openssl \
    -Dcurl=enabled \
    -Dgpgme=disabled \
    -Ddoc=disabled \
    -Ddoxygen=disabled \
    -Di18n=false \
    -Dbuildtype=release \
    -Db_pie=true

ninja -C build -j"$(nproc)"

DESTDIR="$BUILD_DIR/destdir" ninja -C build install

mkdir -p "$SYSROOT/bin" "$SYSROOT/lib64" "$SYSROOT/etc"
cp -r "$BUILD_DIR/destdir/$TARGET_PREFIX"/* "$SYSROOT/" 2>/dev/null || true
if [[ -d "$SYSROOT/lib" ]]; then
    cp -P "$SYSROOT/lib"/libalpm* "$SYSROOT/lib64/" 2>/dev/null || true
fi

log_success "pacman ${PACMAN_TAG}构建安装完成!"
