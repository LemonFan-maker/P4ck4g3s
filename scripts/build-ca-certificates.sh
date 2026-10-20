#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"
source "$SCRIPT_DIR/ca-bundle.sh"

CACERT_VER="$(manifest_require_version ca-certificates)"
STAGING_DIR="$BUILD_DIR/staging_ca_certificates"

log_info ">>> 开始构建ca-certificates(${CACERT_VER})..."
mkdir -p "$BUILD_DIR"

ensure_ca_bundle
PEM="$CA_BUNDLE_PATH"

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
