#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

NCURSES_REPO="https://github.com/ThomasDickey/ncurses-snapshots.git"
NCURSES_VER="6.5"
NCURSES_TAR="ncurses-${NCURSES_VER}.tar.gz"
NCURSES_URL="https://invisible-mirror.net/archives/ncurses/${NCURSES_TAR}"
SRC_DIR="$BUILD_DIR/ncurses"

log_info ">>> 开始从GitHub/GitLab浅克隆最新代码并构建ncurses(master)..."
if ! git_clone_latest "$NCURSES_REPO" "$SRC_DIR" "master" 2>/dev/null; then
    log_info "Git克隆受限,自动回退至官方发布镜像源..."
    download_tarball "$NCURSES_URL" "$NCURSES_TAR"
    rm -rf "$SRC_DIR"
    mkdir -p "$SRC_DIR"
    tar -xzf "$DOWNLOADS_DIR/$NCURSES_TAR" -C "$BUILD_DIR"
    if [[ -d "$BUILD_DIR/ncurses-${NCURSES_VER}" ]]; then
        mv "$BUILD_DIR/ncurses-${NCURSES_VER}"/* "$SRC_DIR/" 2>/dev/null || true
    fi
fi
apply_patches "ncurses" "$SRC_DIR"

cd "$SRC_DIR"
export CPPFLAGS="-D_GNU_SOURCE -I$SYSROOT/include"
export CFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I$SYSROOT/include"
export LDFLAGS="-L$SYSROOT/lib -L$SYSROOT/lib64 -Wl,-rpath,'\$ORIGIN/../lib64' -Wl,--enable-new-dtags"

./configure \
    --host="$TARGET_TRIPLE" \
    --prefix="$SYSROOT" \
    --sysconfdir="/system/0vl0ad3r/etc" \
    --mandir="/system/0vl0ad3r/share/man" \
    --with-shared \
    --without-normal \
    --without-debug \
    --without-ada \
    --without-manpages \
    --without-tests \
    --without-progs \
    --enable-widec \
    --enable-termcap \
    --enable-ext-colors \
    --enable-ext-mouse \
    --with-pkg-config-libdir="$SYSROOT/lib64/pkgconfig" \
    --with-terminfo-dirs="/system/0vl0ad3r/share/terminfo:/system/etc/terminfo" \
    --with-default-terminfo-dir="/system/0vl0ad3r/share/terminfo"

make -j"$(nproc)"
make install TICDIR="$SYSROOT/share/terminfo" || {
    log_info "完整terminfo安装遇到宿主环境限制,执行核心库与头文件安全安装..."
    make install.libs
    make install.includes
}

NCURSES_CURSES_H="$SYSROOT/include/ncursesw/curses.h"
[[ -f "$NCURSES_CURSES_H" ]] || NCURSES_CURSES_H="$SYSROOT/include/ncurses/curses.h"
if [[ ! -f "$NCURSES_CURSES_H" ]]; then
    log_error "安装后找不到curses.h,无法确定ncurses实际版本"
    exit 1
fi
BUILT_VER="$(sed -n 's/^#define[[:space:]]\+NCURSES_VERSION[[:space:]]\+"\([^"]*\)".*/\1/p' "$NCURSES_CURSES_H" | head -1)"
if [[ -z "$BUILT_VER" ]]; then
    log_error "无法从$NCURSES_CURSES_H解析NCURSES_VERSION,拒绝用猜测值打包"
    exit 1
fi
if [[ "$BUILT_VER" != "$NCURSES_VER" ]]; then
    log_info "源码版本$BUILT_VER与下载版本$NCURSES_VER不同(走的是git master),pkgver取实际构建值$BUILT_VER"
fi
NCURSES_VER="$BUILT_VER"
NCURSES_VER="$(git_pkgver "$SRC_DIR" "$NCURSES_VER")"

cd "$SYSROOT"
mkdir -p lib64 include/ncurses include/ncursesw
if [[ -d lib ]]; then
    cp -P lib/libncurses* lib/libform* lib/libmenu* lib/libpanel* lib64/ 2>/dev/null || true
fi

cd "$SYSROOT/lib64"
ln -sf libncursesw.so libncurses.so 2>/dev/null || true
ln -sf libncursesw.so libcurses.so 2>/dev/null || true
ln -sf libncursesw.so libtinfo.so 2>/dev/null || true

cd "$SYSROOT/include"
for h in curses.h ncurses.h term.h termcap.h unctrl.h; do
    if [[ -f "ncursesw/$h" ]]; then
        ln -sf "ncursesw/$h" "$h" 2>/dev/null || true
        ln -sf "../ncursesw/$h" "ncurses/$h" 2>/dev/null || true
    fi
done

for term_name in xterm xterm-256color screen screen-256color tmux tmux-256color vt100 linux dumb; do
    first_char="${term_name:0:1}"
    if [[ -f "/usr/share/terminfo/$first_char/$term_name" ]]; then
        mkdir -p "$SYSROOT/share/terminfo/$first_char"
        cp -a "/usr/share/terminfo/$first_char/$term_name" "$SYSROOT/share/terminfo/$first_char/"
    elif [[ -f "/lib/terminfo/$first_char/$term_name" ]]; then
        mkdir -p "$SYSROOT/share/terminfo/$first_char"
        cp -a "/lib/terminfo/$first_char/$term_name" "$SYSROOT/share/terminfo/$first_char/"
    fi
done

STAGING_DIR="$BUILD_DIR/staging_ncurses"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/lib64" "$STAGING_DIR/include" "$STAGING_DIR/share"

cp -P "$SYSROOT/lib64"/libncurses* "$STAGING_DIR/lib64/" 2>/dev/null || true
cp -P "$SYSROOT/lib64"/libcurses* "$STAGING_DIR/lib64/" 2>/dev/null || true
cp -P "$SYSROOT/lib64"/libtinfo* "$STAGING_DIR/lib64/" 2>/dev/null || true
cp -P "$SYSROOT/lib64"/libform* "$STAGING_DIR/lib64/" 2>/dev/null || true
cp -P "$SYSROOT/lib64"/libmenu* "$STAGING_DIR/lib64/" 2>/dev/null || true
cp -P "$SYSROOT/lib64"/libpanel* "$STAGING_DIR/lib64/" 2>/dev/null || true
cp -a "$SYSROOT/include/ncurses"* "$STAGING_DIR/include/" 2>/dev/null || true
if [[ -d "$SYSROOT/share/terminfo" ]]; then
    cp -a "$SYSROOT/share/terminfo" "$STAGING_DIR/share/" 2>/dev/null || true
fi
if [[ -d "$SYSROOT/share/tabset" ]]; then
    cp -a "$SYSROOT/share/tabset" "$STAGING_DIR/share/" 2>/dev/null || true
fi

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "ncurses" \
    "$NCURSES_VER" \
    "1" \
    "System V Release 4.0 curses终端显示核心库(包含wide-character及terminfo数据库)" \
    "https://invisible-island.net/ncurses/" \
    "MIT" \
    "base-layout"

log_success "ncurses构建与打包完成!"
