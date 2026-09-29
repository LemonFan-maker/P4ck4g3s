#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"

STAGING_DIR="$BUILD_DIR/staging_curl"

if [[ ! -f "$SYSROOT/lib64/libssl.so" || ! -f "$SYSROOT/lib64/libzstd.so" ]]; then
    log_info "检测到底层网络/压缩依赖缺失,执行前置编译..."
    "$REPO_ROOT/bootstrap/build-zlib.sh"
    "$REPO_ROOT/bootstrap/build-zstd.sh"
    "$REPO_ROOT/bootstrap/build-openssl.sh"
fi

if [[ ! -f "$SYSROOT/lib64/libcurl.so" ]]; then
    log_info "检测到sysroot缺少libcurl,执行前置编译..."
    "$REPO_ROOT/bootstrap/build-curl.sh"
fi

SRC_DIR="$BUILD_DIR/curl"

CURLVER_H="$SYSROOT/include/curl/curlver.h"
if [[ ! -f "$CURLVER_H" ]]; then
    log_error "sysroot缺少$CURLVER_H,拒绝打包"
    log_error "若sysroot不完整,请先执行./bootstrap/build-curl.sh"
    exit 1
fi

RAW_VER=$(sed -n 's/.*LIBCURL_VERSION *"\([^"]*\)".*/\1/p' "$CURLVER_H" | head -1)
if [[ -z "$RAW_VER" ]]; then
    log_error "无法从$CURLVER_H解析curl版本,拒绝打包"
    log_error "若sysroot不完整,请先执行./bootstrap/build-curl.sh"
    exit 1
fi

if [[ "$RAW_VER" == *-DEV* ]]; then
    COMMIT=$(git -C "$SRC_DIR" rev-parse --short HEAD 2>/dev/null || true)
    if [[ -z "$COMMIT" ]]; then
        log_error "无法从$SRC_DIR取得commit,拒绝打包"
        log_error "版本号必须能唯一标识构建,否则客户端无法升级"
        exit 1
    fi
    CURRENT_VER="${RAW_VER%-DEV}.$(date -u +%Y%m%d%H%M%S).g${COMMIT}"
else
    CURRENT_VER="$RAW_VER"
fi

log_info ">>> 正在从sysroot收集curl(${CURRENT_VER})并打包..."

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/include"

cp -a "$SYSROOT/bin/curl" "$STAGING_DIR/bin/"
if [[ -f "$SYSROOT/bin/curl-config" ]]; then
    cp -a "$SYSROOT/bin/curl-config" "$STAGING_DIR/bin/"
fi

cp -a "$SYSROOT/include/curl" "$STAGING_DIR/include/"

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "curl" \
    "$CURRENT_VER" \
    "1" \
    "多协议命令行传输工具与核心库(支持OpenSSL/zstd/HTTP2/Bionic优化)" \
    "https://curl.se/" \
    "curl" \
    "base-layout" "ca-certificates"

log_success "curl打包完成!"
