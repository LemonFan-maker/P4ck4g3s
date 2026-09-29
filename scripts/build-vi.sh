#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

VI_VER="$(manifest_require_version vi)"
STAGING_DIR="$BUILD_DIR/staging_vi"

log_info ">>> 开始打包vi metapackage(${VI_VER})..."

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "vi" \
    "$VI_VER" \
    "1" \
    "$(manifest_desc vi)" \
    "https://github.com/LemonFan-maker/P4ck4g3s" \
    "Apache-2.0" \
    "vim"

log_success "vi构建与打包完成!"
