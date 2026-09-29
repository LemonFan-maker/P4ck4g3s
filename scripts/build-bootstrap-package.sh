#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"

STAGE="$BUILD_DIR/stage_bootstrap_pkg"

BOOTSTRAP_BINS=(pacman pacman-conf zstd zstdcat unzstd xz lzmadec)

log_info ">>> 正在从sysroot收集pacman自举二进制..."

rm -rf "$STAGE"
mkdir -p "$STAGE/bin"

MISSING=()
for b in "${BOOTSTRAP_BINS[@]}"; do
    if [[ -f "$SYSROOT/bin/$b" ]]; then
        cp -a "$SYSROOT/bin/$b" "$STAGE/bin/$b"
    else
        MISSING+=("$b")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    log_error "sysroot中缺少自举二进制:${MISSING[*]}"
    log_error "请先执行对应的bootstrap/build-*.sh(zstd/xz/pacman),否则封装出的包无法运行"
    exit 1
fi

PACMAN_VERSION="$(sed -n 's/^PACMAN_TAG="v\?\([0-9][0-9.]*\)".*/\1/p' "$REPO_ROOT/bootstrap/build-pacman.sh" | head -1)"
if [[ -z "$PACMAN_VERSION" ]]; then
    log_error "无法从bootstrap/build-pacman.sh解析PACMAN_TAG,拒绝用猜测版本打包"
    exit 1
fi
BOOTSTRAP_VER="$PACMAN_VERSION"
BOOTSTRAP_REL="1"

log_info ">>> pacman自举包归属文件清单:"
(cd "$STAGE" && find . -mindepth 1 -not -type d -printf '%P\n' | sort)

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGE" \
    "pacman" \
    "$BOOTSTRAP_VER" \
    "$BOOTSTRAP_REL" \
    "Arch pacman包管理器(Bionic aarch64原生版)及配套的zstd/xz二进制" \
    "https://github.com/LemonFan-maker/P4ck4g3s" \
    "GPL-2.0-or-later" \
    "base-layout" "ca-certificates"

log_success "pacman包生成完成:output/repo/pacman-${BOOTSTRAP_VER}-${BOOTSTRAP_REL}-aarch64.pkg.tar.zst"
