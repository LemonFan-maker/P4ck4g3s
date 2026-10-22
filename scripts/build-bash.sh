#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

SRC_DIR="$BUILD_DIR/bash"
STAGING_DIR="$BUILD_DIR/staging_bash"
DEST_DIR="$BUILD_DIR/dest_bash"

if [[ ! -f "$SYSROOT/lib64/libncursesw.so" && ! -f "$SYSROOT/lib/libncursesw.so" ]]; then
    log_info "检测到依赖库ncurses缺失,正在前置构建ncurses..."
    "$REPO_ROOT/bootstrap/build-ncurses.sh"
fi

log_info ">>> 开始构建bash(清单钉住$(manifest_require_version bash))..."
fetch_source bash "$SRC_DIR"
apply_patches "bash" "$SRC_DIR" 0

cd "$SRC_DIR"

CURRENT_VER="$(manifest_require_version bash)"
BASE_VER="${CURRENT_VER%.*}"
SOURCE_PATCHLEVEL="$(sed -n 's/^#define[[:space:]]\+PATCHLEVEL[[:space:]]\+\([0-9][0-9]*\).*/\1/p' patchlevel.h | head -1)"
if [[ -z "$SOURCE_PATCHLEVEL" ]]; then
    log_error "无法从patchlevel.h解析PATCHLEVEL,拒绝打包"
    exit 1
fi
SOURCE_VER="$BASE_VER.$SOURCE_PATCHLEVEL"
if [[ "$CURRENT_VER" != "$SOURCE_VER" ]]; then
    log_error "bash版本与清单不符:源码为$SOURCE_VER,清单为$CURRENT_VER"
    log_error "请确认patches/bash里的官方补丁已覆盖到对应patchlevel,或运行./scripts/sync-archlinux.py刷新清单"
    exit 1
fi

rm -rf "$STAGING_DIR" "$DEST_DIR"
mkdir -p "$STAGING_DIR/etc"

BASH_DEFS=(
    "-DDEFAULT_PATH_VALUE='\"/system/0vl0ad3r/bin:/system/bin\"'"
    "-DSTANDARD_UTILS_PATH='\"/system/bin\"'"
    "-DSYS_BASHRC='\"/system/0vl0ad3r/etc/bash.bashrc\"'"
    "-DSYS_BASH_LOGOUT='\"/system/0vl0ad3r/etc/bash.bash_logout\"'"
    "-DNON_INTERACTIVE_LOGIN_SHELLS"
    "-std=gnu17"
)
export CFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I$SYSROOT/include -I$SYSROOT/include/ncursesw ${BASH_DEFS[*]}"
export LDFLAGS="-L$SYSROOT/lib -L$SYSROOT/lib64 -Wl,-rpath,'\$ORIGIN/../lib64' -Wl,--enable-new-dtags"

./configure \
    --host="$TARGET_TRIPLE" \
    --prefix="$TARGET_PREFIX" \
    --sysconfdir="$TARGET_PREFIX/etc" \
    --mandir="$TARGET_PREFIX/share/man" \
    --infodir="$TARGET_PREFIX/share/info" \
    --with-curses \
    --enable-readline \
    --without-bash-malloc \
    --disable-nls

make -j"$(nproc)" CFLAGS_FOR_BUILD="-O2 -std=gnu17 -DCROSS_COMPILING"
make DESTDIR="$DEST_DIR" install

cp -a "$DEST_DIR$TARGET_PREFIX/." "$STAGING_DIR/"

ln -sf bash "$STAGING_DIR/bin/sh"
ln -sf bash "$STAGING_DIR/bin/rbash"

rm -f "$STAGING_DIR/share/info/dir"

cat <<'EOF' > "$STAGING_DIR/etc/bash.bashrc"
# 0vl0ad3r system-wide bashrc
case $- in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac

if [ -r /system/0vl0ad3r/etc/0vl0ad3r.env ]; then
    . /system/0vl0ad3r/etc/0vl0ad3r.env
fi

export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-C.UTF-8}"
export HISTFILE="${HISTFILE:-/data/local/tmp/.bash_history}"
HISTSIZE=2000
HISTFILESIZE=10000

shopt -s checkwinsize 2>/dev/null || true
PS1='\[\e[1;36m\]0vl0ad3r\[\e[0m\]:\w\$ '
EOF

cat <<'EOF' > "$STAGING_DIR/etc/bash.bash_logout"
history -a 2>/dev/null || true
EOF

cat <<'EOF' > "$STAGING_DIR/etc/profile"
# 0vl0ad3r login profile
if [ -r /system/0vl0ad3r/etc/0vl0ad3r.env ]; then
    . /system/0vl0ad3r/etc/0vl0ad3r.env
fi
if [ -r /system/0vl0ad3r/etc/bash.bashrc ]; then
    . /system/0vl0ad3r/etc/bash.bashrc
fi
EOF

chmod 755 "$STAGING_DIR/bin/bash" "$STAGING_DIR/bin/bashbug" 2>/dev/null || true
chmod 644 "$STAGING_DIR/etc/bash.bashrc" "$STAGING_DIR/etc/bash.bash_logout" "$STAGING_DIR/etc/profile"

cp -a "$STAGING_DIR/." "$SYSROOT/"

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "bash" \
    "$CURRENT_VER" \
    "1" \
    "$(manifest_desc bash)" \
    "https://www.gnu.org/software/bash/bash.html" \
    "GPL-3.0-or-later" \
    "base-layout" "ncurses"

log_success "bash构建与打包完成!"
