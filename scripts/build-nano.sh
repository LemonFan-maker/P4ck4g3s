#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

SRC_DIR="$BUILD_DIR/nano"
STAGING_DIR="$BUILD_DIR/staging_nano"

if [[ ! -f "$SYSROOT/lib64/libncursesw.so" && ! -f "$SYSROOT/lib/libncursesw.so" ]]; then
    log_info "检测到依赖库ncurses缺失,正在前置构建ncurses..."
    "$REPO_ROOT/bootstrap/build-ncurses.sh"
fi

log_info ">>> 开始构建nano(清单钉住$(manifest_require_version nano))..."
fetch_source nano "$SRC_DIR"
apply_patches "nano" "$SRC_DIR"

cd "$SRC_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/etc" "$STAGING_DIR/share/nano"

if [[ ! -f configure && -f autogen.sh ]]; then
    log_info "正在生成configure脚本(autogen.sh)..."
    if ! ./autogen.sh; then
        log_error "autogen.sh失败,改用autoreconf -fi..."
        autoreconf -fi || {
            log_error "autogen.sh与autoreconf -fi都失败,nano无法生成configure"
            log_error "宿主需要autoconf / automake / libtool / gettext"
            exit 1
        }
    fi
fi

if [[ ! -f configure ]]; then
    log_error "nano源码树缺少configure,拒绝构建"
    log_error "清单钉住的官方发布tarball自带configure,缺失说明取到了错误产物"
    exit 1
fi

CURRENT_VER="$(manifest_require_version nano)"

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
    "$(manifest_desc nano)" \
    "https://www.nano-editor.org/" \
    "GPL-3.0-or-later" \
    "base-layout"

log_success "nano构建与打包完成!"
