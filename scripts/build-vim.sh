#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"

VIM_REPO="https://github.com/vim/vim.git"
SRC_DIR="$BUILD_DIR/vim"
STAGING_DIR="$BUILD_DIR/staging_vim"

if [[ ! -f "$SYSROOT/lib64/libncursesw.so" && ! -f "$SYSROOT/lib/libncursesw.so" ]]; then
    log_info "检测到依赖库ncurses缺失,正在前置构建ncurses..."
    "$REPO_ROOT/bootstrap/build-ncurses.sh"
fi

log_info ">>> 开始从GitHub浅克隆最新代码并构建Vim(master)..."
git_clone_latest "$VIM_REPO" "$SRC_DIR" "master"
apply_patches "vim" "$SRC_DIR"

cd "$SRC_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/etc" "$STAGING_DIR/share"

VMAJOR=$(sed -n 's/^#define[[:space:]]\+VIM_VERSION_MAJOR[[:space:]]\+\([0-9]\{1,\}\).*/\1/p' src/version.h | head -1)
VMINOR=$(sed -n 's/^#define[[:space:]]\+VIM_VERSION_MINOR[[:space:]]\+\([0-9]\{1,\}\).*/\1/p' src/version.h | head -1)
VBUILD=$(sed -n 's/^#define[[:space:]]\+VIM_VERSION_BUILD[[:space:]]\+\([0-9]\{1,\}\).*/\1/p' src/version.h | head -1)
if [[ -z "$VMAJOR" || -z "$VMINOR" || -z "$VBUILD" ]]; then
    log_error "无法从src/version.h解析vim版本(MAJOR=$VMAJOR MINOR=$VMINOR BUILD=$VBUILD),拒绝打包"
    exit 1
fi

CURRENT_VER="$(git_pkgver "$SRC_DIR" "${VMAJOR}.${VMINOR}.${VBUILD}")"

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
    "全功能高级终端文本编辑器(Vi IMproved,包含xxd/语法高亮/Unicode支持)" \
    "https://www.vim.org/" \
    "Vim" \
    "base-layout"

log_success "vim构建与打包完成!"
