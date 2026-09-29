#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/../scripts/manifest.sh"

NCURSES_VER="$(manifest_require_version ncurses)"
SRC_DIR="$BUILD_DIR/ncurses"

log_info ">>> 开始构建ncurses(清单钉住官方发布tarball ${NCURSES_VER})..."
fetch_source ncurses "$SRC_DIR"
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
    log_error "ncurses版本与清单不符:源码为$BUILT_VER,清单为$NCURSES_VER"
    log_error "请运行./scripts/sync-archlinux.py刷新清单,或确认tar地址是否已指向新版本"
    exit 1
fi

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
    "$(manifest_desc ncurses)" \
    "https://invisible-island.net/ncurses/" \
    "MIT" \
    "base-layout"

log_success "ncurses构建与打包完成!"
