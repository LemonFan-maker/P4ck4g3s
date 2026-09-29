#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

SRC_DIR="$BUILD_DIR/vim"
STAGING_DIR="$BUILD_DIR/staging_vim"

if [[ ! -f "$SYSROOT/lib64/libncursesw.so" && ! -f "$SYSROOT/lib/libncursesw.so" ]]; then
    log_info "检测到依赖库ncurses缺失,正在前置构建ncurses..."
    "$REPO_ROOT/bootstrap/build-ncurses.sh"
fi

log_info ">>> 开始构建Vim(清单钉住$(manifest_ref vim))..."
fetch_source vim "$SRC_DIR"
apply_patches "vim" "$SRC_DIR"

cd "$SRC_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/etc" "$STAGING_DIR/share"

VMAJOR=$(sed -n 's/^#define[[:space:]]\+VIM_VERSION_MAJOR[[:space:]]\+\([0-9]\{1,\}\).*/\1/p' src/version.h | head -1)
VMINOR=$(sed -n 's/^#define[[:space:]]\+VIM_VERSION_MINOR[[:space:]]\+\([0-9]\{1,\}\).*/\1/p' src/version.h | head -1)
VPATCH=$(awk '/static int included_patches/,/^};/' src/version.c \
    | sed -n 's/^[[:space:]]*\([0-9][0-9]*\),[[:space:]]*$/\1/p' | head -1)
if [[ -z "$VMAJOR" || -z "$VMINOR" || -z "$VPATCH" ]]; then
    log_error "无法解析vim版本(MAJOR=$VMAJOR MINOR=$VMINOR PATCH=$VPATCH),拒绝打包"
    exit 1
fi

SOURCE_VER="${VMAJOR}.${VMINOR}.${VPATCH}"
CURRENT_VER="$(manifest_require_version vim)"
if [[ "$CURRENT_VER" != "$SOURCE_VER" ]]; then
    log_error "vim版本与清单不符:源码为$SOURCE_VER,清单为$CURRENT_VER"
    log_error "请运行./scripts/sync-archlinux.py刷新清单,或确认ref是否已指向新版本"
    exit 1
fi

export vim_cv_toupper_broken=no
export vim_cv_terminfo=yes
export vim_cv_tgetent=zero
export vim_cv_tty_group=world
export vim_cv_getcwd_broken=no
export vim_cv_stat_ignores_slash=no
export vim_cv_memmove_handles_overlap=yes
export vim_cv_timer_create=yes

export CFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I$SYSROOT/include -I$SYSROOT/include/ncursesw"
export LDFLAGS="-L$SYSROOT/lib -L$SYSROOT/lib64 -lncursesw -Wl,-rpath,'\$ORIGIN/../lib64' -Wl,--enable-new-dtags"

./configure \
    --host="$TARGET_TRIPLE" \
    --prefix="$TARGET_PREFIX" \
    --sysconfdir="$TARGET_PREFIX/etc" \
    --mandir="$TARGET_PREFIX/share/man" \
    --with-tlib=ncursesw \
    --enable-gui=no \
    --without-x \
    --disable-nls \
    --disable-gpm \
    --disable-sysmouse \
    --disable-selinux \
    --disable-xsmp \
    --enable-multibyte \
    --with-features=normal

make -j"$(nproc)"
rm -rf "$BUILD_DIR/dest_vim"
make install DESTDIR="$BUILD_DIR/dest_vim"

cp -a "$BUILD_DIR/dest_vim/system/0vl0ad3r"/* "$SYSROOT/" 2>/dev/null || true
cp -a "$BUILD_DIR/dest_vim/system/0vl0ad3r"/* "$STAGING_DIR/" 2>/dev/null || true
ln -sf vim "$STAGING_DIR/bin/vimdiff"
ln -sf vim "$STAGING_DIR/bin/view"
ln -sf vim "$STAGING_DIR/bin/rview"
ln -sf vim "$STAGING_DIR/bin/rvim"
ln -sf vim "$STAGING_DIR/bin/vi"

if [[ -f "$BUILD_DIR/dest_vim/system/0vl0ad3r/bin/xxd" ]]; then
    cp -a "$BUILD_DIR/dest_vim/system/0vl0ad3r/bin/xxd" "$STAGING_DIR/bin/"
elif [[ -f src/xxd/xxd ]]; then
    cp -a src/xxd/xxd "$STAGING_DIR/bin/"
fi

if [[ -d "$SYSROOT/share/vim" ]]; then
    cp -a "$SYSROOT/share/vim" "$STAGING_DIR/share/"
elif [[ -d runtime ]]; then
    mkdir -p "$STAGING_DIR/share/vim/vim91"
    cp -a runtime/* "$STAGING_DIR/share/vim/vim91/"
fi

cat <<'EOF' > "$STAGING_DIR/etc/vimrc"
set nocompatible
syntax on
filetype plugin indent on

set encoding=utf-8
set fileencodings=utf-8,gbk,gb2312,latin1
set termencoding=utf-8

set number
set relativenumber
set cursorline
set showcmd
set showmode
set wildmenu

set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set smartindent

set hlsearch
set incsearch
set ignorecase
set smartcase

set mouse=a
set backspace=indent,eol,start
EOF

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "vim" \
    "$CURRENT_VER" \
    "1" \
    "$(manifest_desc vim)" \
    "https://www.vim.org/" \
    "Vim" \
    "base-layout"

log_success "vim构建与打包完成!"
