#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"

NANO_REPO="https://git.savannah.gnu.org/git/nano.git"
NANO_VER="latest"
NANO_TAR="nano-8.3.tar.xz"
NANO_URL="https://www.nano-editor.org/dist/v8/${NANO_TAR}"
NANO_URL_FALLBACK="https://ftp.gnu.org/gnu/nano/${NANO_TAR}"
SRC_DIR="$BUILD_DIR/nano"
STAGING_DIR="$BUILD_DIR/staging_nano"

if [[ ! -f "$SYSROOT/lib64/libncursesw.so" && ! -f "$SYSROOT/lib/libncursesw.so" ]]; then
    log_info "检测到依赖库ncurses缺失,正在前置构建ncurses..."
    "$REPO_ROOT/bootstrap/build-ncurses.sh"
fi

log_info ">>> 开始从Git仓库浅克隆最新代码并构建nano(master)..."

if ! git_clone_latest "$NANO_REPO" "$SRC_DIR" "master" 2>/dev/null; then
    log_info "Git克隆受限,自动回退至官方发布镜像源..."
    download_tarball "$NANO_URL" "$NANO_TAR" || download_tarball "$NANO_URL_FALLBACK" "$NANO_TAR"
    rm -rf "$SRC_DIR"
    mkdir -p "$SRC_DIR"
    tar -xf "$DOWNLOADS_DIR/$NANO_TAR" -C "$BUILD_DIR"
    if [[ -d "$BUILD_DIR/nano-8.3" ]]; then
        mv "$BUILD_DIR/nano-8.3"/* "$SRC_DIR/" 2>/dev/null || true
    fi
fi
apply_patches "nano" "$SRC_DIR"

cd "$SRC_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/etc" "$STAGING_DIR/share/nano"

if [[ ! -f configure && -f autogen.sh ]]; then
    log_info "正在生成configure脚本(autogen.sh)..."
    ./autogen.sh 2>/dev/null || autoreconf -fi 2>/dev/null || true
fi

if [[ ! -f configure ]]; then
    log_info "Git源码树缺少预构建configure,自动加载官方发布镜像包..."
    download_tarball "$NANO_URL" "$NANO_TAR" || download_tarball "$NANO_URL_FALLBACK" "$NANO_TAR"
    rm -rf "$SRC_DIR"
    mkdir -p "$SRC_DIR"
    tar -xf "$DOWNLOADS_DIR/$NANO_TAR" --strip-components=1 -C "$SRC_DIR"
    apply_patches "nano" "$SRC_DIR"
    cd "$SRC_DIR"
fi

CURRENT_VER=$(sed -n "s/^PACKAGE_VERSION='\([^']*\)'.*/\1/p" configure 2>/dev/null | head -1 || true)
if [[ -z "$CURRENT_VER" ]]; then
    log_error "无法从configure解析nano的PACKAGE_VERSION,拒绝打包"
    exit 1
fi
CURRENT_VER="$(git_pkgver "$SRC_DIR" "$CURRENT_VER")"

export CFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I$SYSROOT/include -I$SYSROOT/include/ncursesw"
export LDFLAGS="-L$SYSROOT/lib -L$SYSROOT/lib64 -lncursesw -Wl,-rpath,'\$ORIGIN/../lib64' -Wl,--enable-new-dtags"

./configure \
    --host="$TARGET_TRIPLE" \
    --prefix="$TARGET_PREFIX" \
    --sysconfdir="$TARGET_PREFIX/etc" \
    --mandir="$TARGET_PREFIX/share/man" \
    --disable-nls \
    --enable-utf8 \
    --enable-color \
    --enable-extra \
    --enable-multibuffer \
    --enable-nanorc \
    --enable-histories \
    --enable-linenumbers \
    NCURSESW_CFLAGS="-I$SYSROOT/include -I$SYSROOT/include/ncursesw" \
    NCURSESW_LIBS="-L$SYSROOT/lib64 -lncursesw"

make -j"$(nproc)"
rm -rf "$BUILD_DIR/dest_nano"
make install DESTDIR="$BUILD_DIR/dest_nano"

cp -a "$BUILD_DIR/dest_nano/system/0vl0ad3r"/* "$SYSROOT/" 2>/dev/null || true
cp -a "$BUILD_DIR/dest_nano/system/0vl0ad3r"/* "$STAGING_DIR/" 2>/dev/null || true

rm -f "$STAGING_DIR/share/info/dir"
ln -sf nano "$STAGING_DIR/bin/rnano"

if [[ -d syntax && ! -d "$STAGING_DIR/share/nano" ]]; then
    mkdir -p "$STAGING_DIR/share/nano"
    cp -a syntax/*.nanorc "$STAGING_DIR/share/nano/" 2>/dev/null || true
fi

cat <<'EOF' > "$STAGING_DIR/etc/nanorc"
set autoindent
set constantshow
set linenumbers
set mouse
set smooth
set tabsize 4
set tabstospaces
set zap

include "/system/0vl0ad3r/share/nano/*.nanorc"
EOF

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "nano" \
    "$CURRENT_VER" \
    "1" \
    "轻量级全功能终端文本编辑器(GNU nano,带完整高亮与UTF-8支持)" \
    "https://www.nano-editor.org/" \
    "GPL-3.0-or-later" \
    "base-layout"

log_success "nano构建与打包完成!"
