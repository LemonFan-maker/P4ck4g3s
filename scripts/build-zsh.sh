#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

SRC_DIR="$BUILD_DIR/zsh"
STAGING_DIR="$BUILD_DIR/staging_zsh"
DEST_DIR="$BUILD_DIR/dest_zsh"
ZSH_PKGREL="2"

if [[ ! -f "$SYSROOT/lib64/libncursesw.so" && ! -f "$SYSROOT/lib/libncursesw.so" ]]; then
    log_info "检测到依赖库ncurses缺失,正在前置构建ncurses..."
    "$REPO_ROOT/bootstrap/build-ncurses.sh"
fi

log_info ">>> 开始构建zsh(清单钉住$(manifest_require_version zsh))..."
fetch_source zsh "$SRC_DIR"
apply_patches "zsh" "$SRC_DIR"

cd "$SRC_DIR"

CURRENT_VER="$(manifest_require_version zsh)"
SOURCE_VER="$(sed -n 's/^VERSION=\([0-9][0-9.]*\).*/\1/p' Config/version.mk | head -1)"
if [[ -z "$SOURCE_VER" ]]; then
    log_error "无法从Config/version.mk解析VERSION,拒绝打包"
    exit 1
fi
if [[ "$CURRENT_VER" != "$SOURCE_VER" ]]; then
    log_error "zsh版本与清单不符:源码为$SOURCE_VER,清单为$CURRENT_VER"
    log_error "请运行./scripts/sync-archlinux.py刷新清单,或确认tar地址是否已指向新版本"
    exit 1
fi

rm -rf "$STAGING_DIR" "$DEST_DIR"
mkdir -p "$STAGING_DIR"

./configure \
    --host="$TARGET_TRIPLE" \
    --prefix="$TARGET_PREFIX" \
    --sysconfdir="$TARGET_PREFIX/etc" \
    --mandir="$TARGET_PREFIX/share/man" \
    --enable-etcdir="$TARGET_PREFIX/etc/zsh" \
    --enable-zshenv="$TARGET_PREFIX/etc/zsh/zshenv" \
    --enable-zprofile="$TARGET_PREFIX/etc/zsh/zprofile" \
    --enable-zshrc="$TARGET_PREFIX/etc/zsh/zshrc" \
    --enable-zlogin="$TARGET_PREFIX/etc/zsh/zlogin" \
    --enable-zlogout="$TARGET_PREFIX/etc/zsh/zlogout" \
    --enable-fndir="$TARGET_PREFIX/share/zsh/functions" \
    --enable-scriptdir="$TARGET_PREFIX/share/zsh/scripts" \
    --with-term-lib="ncursesw" \
    --enable-multibyte \
    --enable-function-subdirs \
    --enable-zsh-secure-free \
    --disable-gdbm \
    --disable-cap \
    --disable-pcre

make -j"$(nproc)"
make DESTDIR="$DEST_DIR" install

cp -a "$DEST_DIR$TARGET_PREFIX/." "$STAGING_DIR/"

ZSH_SYNTAX_DIR="$BUILD_DIR/zsh-syntax-highlighting"
ZSH_AUTOSUGGEST_DIR="$BUILD_DIR/zsh-autosuggestions"
git_clone_latest "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
    "$ZSH_SYNTAX_DIR" "0.8.0"
git_clone_latest "https://github.com/zsh-users/zsh-autosuggestions.git" \
    "$ZSH_AUTOSUGGEST_DIR" "v0.7.1"

mkdir -p "$STAGING_DIR/share/zsh/plugins"
cp -a "$ZSH_SYNTAX_DIR" "$STAGING_DIR/share/zsh/plugins/zsh-syntax-highlighting"
cp -a "$ZSH_AUTOSUGGEST_DIR" "$STAGING_DIR/share/zsh/plugins/zsh-autosuggestions"
rm -rf \
    "$STAGING_DIR/share/zsh/plugins/zsh-syntax-highlighting/.git" \
    "$STAGING_DIR/share/zsh/plugins/zsh-autosuggestions/.git"

mkdir -p "$STAGING_DIR/etc/zsh"

cat <<'EOF' > "$STAGING_DIR/etc/zsh/zshenv"
# 0vl0ad3r environment: loaded by every zsh, including non-interactive ones.
if [ -r /system/0vl0ad3r/etc/0vl0ad3r.env ]; then
    . /system/0vl0ad3r/etc/0vl0ad3r.env
fi
export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-C.UTF-8}"
EOF

cat <<'EOF' > "$STAGING_DIR/etc/zsh/zprofile"
# 0vl0ad3r login shell profile
if [ -r /system/0vl0ad3r/etc/0vl0ad3r.env ]; then
    . /system/0vl0ad3r/etc/0vl0ad3r.env
fi
EOF

cat <<'EOF' > "$STAGING_DIR/etc/zsh/zshrc"
# 0vl0ad3r interactive zsh defaults
autoload -Uz compinit
compinit -D 2>/dev/null || true
zstyle ':completion:*' menu select

HISTFILE="${HISTFILE:-/data/local/tmp/.zsh_history}"
HISTSIZE=2000
SAVEHIST=10000
setopt hist_ignore_dups share_history

ZSH_PLUGINS=/system/0vl0ad3r/share/zsh/plugins
if [ -r "$ZSH_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
    source "$ZSH_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh"
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
fi
if [ -r "$ZSH_PLUGINS/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
    source "$ZSH_PLUGINS/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

PROMPT='%F{cyan}0vl0ad3r%f:%~%# '
EOF

chmod 644 "$STAGING_DIR/etc/zsh/zshenv" "$STAGING_DIR/etc/zsh/zprofile" "$STAGING_DIR/etc/zsh/zshrc"

cp -a "$STAGING_DIR/." "$SYSROOT/"

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "zsh" \
    "$CURRENT_VER" \
    "$ZSH_PKGREL" \
    "$(manifest_desc zsh)" \
    "https://www.zsh.org/" \
    "MIT" \
    "base-layout" "ncurses"

log_success "zsh构建与打包完成!"
