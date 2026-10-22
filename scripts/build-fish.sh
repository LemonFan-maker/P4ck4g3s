#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

SRC_DIR="$BUILD_DIR/fish"
CMAKE_BUILD_DIR="$BUILD_DIR/fish-build"
STAGING_DIR="$BUILD_DIR/staging_fish"
DEST_DIR="$BUILD_DIR/dest_fish"
FISH_PREFIX_FILE="$BUILD_DIR/fish-install-prefix.cmake"
# pkgrel 2: make the conf.d path handling safe for unset/path-list env vars.
FISH_PKGREL="2"

if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
    log_error "缺少Rust工具链:fish 4.x用Rust重写,需要cargo/rustc"
    log_error "请安装Rust 1.85+并执行:rustup target add aarch64-linux-android"
    exit 1
fi
if command -v rustup >/dev/null 2>&1; then
    if ! rustup target list --installed 2>/dev/null | grep -qx "aarch64-linux-android"; then
        log_error "Rust缺少aarch64-linux-android target"
        log_error "请执行:rustup target add aarch64-linux-android"
        exit 1
    fi
fi

log_info ">>> 开始构建fish(清单钉住$(manifest_require_version fish))..."
fetch_source fish "$SRC_DIR"
apply_patches "fish" "$SRC_DIR"

cd "$SRC_DIR"

CURRENT_VER="$(manifest_require_version fish)"
SOURCE_VER="$(sed -n '/^\[package\]/,/^\[/s/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' Cargo.toml | head -1)"
if [[ -z "$SOURCE_VER" ]]; then
    log_error "无法从Cargo.toml解析fish版本,拒绝打包"
    exit 1
fi
if [[ "$CURRENT_VER" != "$SOURCE_VER" ]]; then
    log_error "fish版本与清单不符:源码为$SOURCE_VER,清单为$CURRENT_VER"
    log_error "请运行./scripts/sync-archlinux.py刷新清单,或确认ref是否已指向新版本"
    exit 1
fi

rm -rf "$CMAKE_BUILD_DIR" "$STAGING_DIR" "$DEST_DIR"
mkdir -p "$STAGING_DIR"

cat <<'EOF' > "$FISH_PREFIX_FILE"
if(DEFINED ENV{TARGET_PREFIX})
    set(CMAKE_INSTALL_PREFIX "$ENV{TARGET_PREFIX}" CACHE PATH "" FORCE)
    set(CMAKE_INSTALL_PREFIX "$ENV{TARGET_PREFIX}")
endif()
EOF

export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CC"
export CC_aarch64_linux_android="$CC"
export AR_aarch64_linux_android="$AR"
export RANLIB_aarch64_linux_android="$RANLIB"
export CFLAGS_aarch64_linux_android="-O2 -fPIC -D_FILE_OFFSET_BITS=64 -I$SYSROOT/include"

cmake -S "$SRC_DIR" -B "$CMAKE_BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
    -DCMAKE_PROJECT_INCLUDE="$FISH_PREFIX_FILE" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_SYSCONFDIR=etc \
    -DRust_CARGO_TARGET=aarch64-linux-android \
    -DRust_CARGO="$(command -v cargo)" \
    -DRust_COMPILER="$(command -v rustc)" \
    -DFISH_USE_SYSTEM_PCRE2=OFF \
    -DWITH_DOCS=OFF \
    -DWITH_MESSAGE_LOCALIZATION=OFF

cmake --build "$CMAKE_BUILD_DIR" --parallel "$(nproc)"
DESTDIR="$DEST_DIR" cmake --install "$CMAKE_BUILD_DIR"

if [[ ! -x "$DEST_DIR$TARGET_PREFIX/bin/fish" ]]; then
    log_error "fish安装后找不到$DEST_DIR$TARGET_PREFIX/bin/fish"
    exit 1
fi
if strings "$DEST_DIR$TARGET_PREFIX/bin/fish" | grep -qF "$SYSROOT"; then
    log_error "fish二进制里仍嵌着构建sysroot路径:$SYSROOT"
    log_error "CMAKE_INSTALL_PREFIX没有在GNUInstallDirs之前修正,拒绝打包"
    exit 1
fi

cp -a "$DEST_DIR$TARGET_PREFIX/." "$STAGING_DIR/"

mkdir -p "$STAGING_DIR/etc/fish/conf.d"
cat <<'EOF' > "$STAGING_DIR/etc/fish/conf.d/0vl0ad3r.fish"
# 0vl0ad3r environment defaults for fish.
set -gx PREFIX /system/0vl0ad3r
if not contains -- $PREFIX/bin $PATH
    set -gx PATH $PREFIX/bin $PATH
end
if not set -q LD_LIBRARY_PATH
    set -gx LD_LIBRARY_PATH $PREFIX/lib64
else if not contains -- $PREFIX/lib64 $LD_LIBRARY_PATH
    set -gx LD_LIBRARY_PATH $PREFIX/lib64 $LD_LIBRARY_PATH
end
set -gx HOME /data/local/tmp
set -gx TMPDIR /data/local/tmp
set -gx TERM xterm-256color
set -gx LANG C.UTF-8
set -gx HISTFILE /data/local/tmp/.fish_history

function fish_prompt
    set_color cyan
    printf '0vl0ad3r'
    set_color normal
    printf ':%s$ ' (prompt_pwd)
end
EOF

chmod 644 "$STAGING_DIR/etc/fish/conf.d/0vl0ad3r.fish"

cp -a "$STAGING_DIR/." "$SYSROOT/"

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "fish" \
    "$CURRENT_VER" \
    "$FISH_PKGREL" \
    "$(manifest_desc fish)" \
    "https://fishshell.com/" \
    "GPL-2.0-only AND BSD-3-Clause AND ISC AND MIT AND PSF-2.0" \
    "base-layout"

log_success "fish构建与打包完成!"
