#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

SRC_DIR="$BUILD_DIR/lm_sensors"
STAGING_DIR="$BUILD_DIR/staging_lm_sensors"
DEST_DIR="$BUILD_DIR/dest_lm_sensors"

log_info ">>> 开始构建lm_sensors(清单钉住$(manifest_require_version lm_sensors))..."
fetch_source lm_sensors "$SRC_DIR"
apply_patches "lm_sensors" "$SRC_DIR"

cd "$SRC_DIR"

CURRENT_VER="$(manifest_require_version lm_sensors)"
SOURCE_VER="$(sed -n 's/^#define[[:space:]]\+LM_VERSION[[:space:]]\+"\([^"]*\)".*/\1/p' version.h | head -1)"
if [[ -z "$SOURCE_VER" ]]; then
    log_error "无法从version.h解析LM_VERSION,拒绝打包"
    exit 1
fi
if [[ "$CURRENT_VER" != "$SOURCE_VER" ]]; then
    log_error "lm_sensors版本与清单不符:源码为$SOURCE_VER,清单为$CURRENT_VER"
    log_error "请运行./scripts/sync-archlinux.py刷新清单,或确认ref是否已指向新版本"
    exit 1
fi

MAKE_ARGS=(
    "CC=$CC"
    "PREFIX=$TARGET_PREFIX"
    "BINDIR=$TARGET_PREFIX/bin"
    "SBINDIR=$TARGET_PREFIX/bin"
    "LIBDIR=$TARGET_PREFIX/lib64"
    "ETCDIR=$TARGET_PREFIX/etc"
    "MANDIR=$TARGET_PREFIX/share/man"
    "BUILD_STATIC_LIB=0"
    "BUILD_SHARED_LIB=1"
    "CFLAGS=-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64"
    "LDFLAGS=-L$SYSROOT/lib -L$SYSROOT/lib64 -Wl,-rpath,$TARGET_PREFIX/lib64 -Wl,--enable-new-dtags"
)

make clean >/dev/null 2>&1 || true
make -j"$(nproc)" "${MAKE_ARGS[@]}"

rm -rf "$DEST_DIR"
make DESTDIR="$DEST_DIR" "${MAKE_ARGS[@]}" install-lib install-prog-sensors

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -a "$DEST_DIR$TARGET_PREFIX"/* "$STAGING_DIR/"
cp -a "$DEST_DIR$TARGET_PREFIX"/* "$SYSROOT/"

mkdir -p "$STAGING_DIR/etc/sensors.d"
install -m 644 "$SRC_DIR/etc/sensors.conf.default" "$STAGING_DIR/etc/sensors3.conf"

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "lm_sensors" \
    "$CURRENT_VER" \
    "1" \
    "$(manifest_desc lm_sensors)" \
    "https://hwmon.wiki.kernel.org/lm_sensors" \
    "GPL-2.0-only OR LGPL-2.1-only" \
    "base-layout"

log_success "lm_sensors构建与打包完成!"
