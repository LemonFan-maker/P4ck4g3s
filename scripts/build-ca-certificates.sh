#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

CACERT_VER="$(manifest_require_version ca-certificates)"
CACERT_NAME="$(manifest_tar ca-certificates)"
CACERT_URL="$(manifest_tar_url ca-certificates)"
CACERT_SHA256="$(manifest_sha256 ca-certificates)"
STAGING_DIR="$BUILD_DIR/staging_ca_certificates"
PEM="$BUILD_DIR/$CACERT_NAME"

if [[ -z "$CACERT_URL" ]]; then
    log_error "清单里ca-certificates没有下载地址,拒绝构建"
    log_error "请检查scripts/sync-archlinux.py的TARBALLS[\"ca-certificates\"]"
    exit 1
fi
if [[ -z "$CACERT_SHA256" ]]; then
    log_error "清单里ca-certificates没有sha256,拒绝构建根证书集"
    log_error "根证书是信任锚,不允许无校验下载;请在sync-archlinux.py里补上校验值"
    exit 1
fi

log_info ">>> 开始构建ca-certificates(${CACERT_VER})..."
mkdir -p "$BUILD_DIR"

if [[ -f "$PEM" ]] && verify_sha256 "$PEM" "$CACERT_SHA256" "ca-certificates"; then
    log_info "复用已缓存且校验通过的$PEM"
else
    rm -f "$PEM"
    log_info "正在下载根证书集:$CACERT_URL"
    curl -fsSL --retry 3 -o "$PEM" "$CACERT_URL"

    if ! verify_sha256 "$PEM" "$CACERT_SHA256" "ca-certificates"; then
        log_error "URL是版本化归档,理论上不可变;校验不过说明该快照被重写或下载损坏"
        log_error "确认无误后:curl -fsSL ${CACERT_URL}.sha256"
        log_error "再更新scripts/sync-archlinux.py中ca-certificates的version与sha256,重新生成清单"
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
    "$(manifest_desc ca-certificates)" \
    "https://curl.se/docs/caextract.html" \
    "MPL-2.0" \
    "base-layout"

log_success "ca-certificates构建与打包完成!"
