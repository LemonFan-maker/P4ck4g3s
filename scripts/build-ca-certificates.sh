#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"

CACERT_VER="2024.09.24"
CACERT_URL="https://curl.se/ca/cacert-2024-09-24.pem"
CACERT_SHA256="189d3cf6d103185fba06d76c1af915263c6d42225481a1759e853b33ac857540"
STAGING_DIR="$BUILD_DIR/staging_ca_certificates"
PEM="$BUILD_DIR/cacert-$CACERT_VER.pem"

log_info ">>> 开始构建ca-certificates($CACERT_VER)..."
mkdir -p "$BUILD_DIR"

if [[ -f "$PEM" ]] && echo "$CACERT_SHA256  $PEM" | sha256sum -c - >/dev/null 2>&1; then
    log_info "复用已缓存且校验通过的$PEM"
else
    rm -f "$PEM"
    log_info "正在下载根证书集:$CACERT_URL"
    curl -fsSL --retry 3 -o "$PEM" "$CACERT_URL"

    if ! echo "$CACERT_SHA256  $PEM" | sha256sum -c - >/dev/null 2>&1; then
        log_error "根证书集校验和不符,拒绝继续构建"
        log_error "期望:$CACERT_SHA256"
        log_error "实际:$(sha256sum "$PEM" | cut -d' ' -f1)"
        log_error "URL是版本化归档,理论上不可变;若确实变了说明该快照被重写:"
        log_error "curl -fsSL $CACERT_URL.sha256"
        log_error "然后同时更新CACERT_URL的日期,CACERT_VER,CACERT_SHA256三者"
        exit 1
    fi
    log_success "根证书集校验通过"
fi

rm -rf "$STAGING_DIR"
install -d -m 755 "$STAGING_DIR/etc/ssl/certs"
install -m 644 "$PEM" "$STAGING_DIR/etc/ssl/cert.pem"
ln -sf ../cert.pem "$STAGING_DIR/etc/ssl/certs/ca-certificates.crt"

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "ca-certificates" \
    "$CACERT_VER" \
    "1" \
    "Mozilla根证书集(PEM格式),支持HTTPS安全传输与证书链校验" \
    "https://curl.se/docs/caextract.html" \
    "MPL-2.0" \
    "base-layout"

log_success "ca-certificates构建与打包完成!"
