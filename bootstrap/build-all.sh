#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

log_info "开始执行0vl0ad3r自举编译"
log_info "目标平台:Android API ${ANDROID_API}(aarch64)"
log_info "目标前缀:${TARGET_PREFIX}"

SECONDS=0
"$SCRIPT_DIR/build-zlib.sh"
"$SCRIPT_DIR/build-zstd.sh"
"$SCRIPT_DIR/build-xz.sh"
"$SCRIPT_DIR/build-openssl.sh"
"$SCRIPT_DIR/build-curl.sh"
"$SCRIPT_DIR/build-archive.sh"
"$SCRIPT_DIR/build-pacman.sh"
"$SCRIPT_DIR/package-bootstrap.sh"

ELAPSED=$SECONDS
log_success "自举打包成功完成!总耗时:${ELAPSED}秒"
log_success "产物位于:${OUTPUT_DIR}/0vl0ad3r-bootstrap-aarch64.tar.zst"
