#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"
source "$SCRIPT_DIR/ca-bundle.sh"

BASE_LAYOUT_VER="$(manifest_require_version base-layout)"
STAGING_DIR="$BUILD_DIR/staging_base_layout"

if [[ -n "${OVL0AD3R_MIRROR:-}" ]]; then
    MIRROR_PRIMARY="$OVL0AD3R_MIRROR"
elif [[ -n "${OVL0AD3R_DOMAIN:-}" ]]; then
    MIRROR_PRIMARY="https://${OVL0AD3R_DOMAIN}"
else
    MIRROR_PRIMARY="https://r3p0.orionisli.com"
fi

log_info ">>> 开始构建base-layout(${BASE_LAYOUT_VER})..."

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

install -d -m 755 "$STAGING_DIR/bin"
install -d -m 755 "$STAGING_DIR/lib64"
install -d -m 755 "$STAGING_DIR/etc/pacman.d"
install -d -m 755 "$STAGING_DIR/etc/pacman.d/gnupg"
install -d -m 755 "$STAGING_DIR/etc/pacman.d/hooks"
install -d -m 755 "$STAGING_DIR/etc/ssl/certs"
install -d -m 755 "$STAGING_DIR/share"
install -d -m 755 "$STAGING_DIR/var/lib/pacman/local"
install -d -m 755 "$STAGING_DIR/var/cache/pacman/pkg"
install -d -m 755 "$STAGING_DIR/var/log"
install -d -m 1777 "$STAGING_DIR/tmp"

ensure_ca_bundle
install -m 644 "$CA_BUNDLE_PATH" "$STAGING_DIR/etc/ssl/bootstrap-ca.pem"

cat <<'EOF' > "$STAGING_DIR/bin/0vl"
#!/system/bin/sh
export PREFIX="/system/0vl0ad3r"
export PATH="$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib64:$LD_LIBRARY_PATH"
export HOME="/data/local/tmp"
export TMPDIR="/data/local/tmp"

case "$1" in
    sh|shell|"")
        exec /system/bin/sh
        ;;
    exec)
        shift
        exec "$@"
        ;;
    *)
        exec "$@"
        ;;
esac
EOF
chmod 755 "$STAGING_DIR/bin/0vl"

cat <<'EOF' > "$STAGING_DIR/etc/pacman.conf"
[options]
RootDir = /system/0vl0ad3r
DBPath = /system/0vl0ad3r/var/lib/pacman/
CacheDir = /system/0vl0ad3r/var/cache/pacman/pkg/
LogFile = /system/0vl0ad3r/var/log/pacman.log
GPGDir = /system/0vl0ad3r/etc/pacman.d/gnupg/
HookDir = /system/0vl0ad3r/etc/pacman.d/hooks/
HoldPkg = pacman base-layout
Architecture = aarch64

SigLevel = Never
LocalFileSigLevel = Optional

Color
CheckSpace
VerbosePkgLists
ILoveCandy

[0vl0ad3r]
Include = /system/0vl0ad3r/etc/pacman.d/mirrorlist
EOF

cat <<EOF > "$STAGING_DIR/etc/pacman.d/mirrorlist"
Server = $MIRROR_PRIMARY
EOF

cat <<'EOF' > "$STAGING_DIR/etc/0vl0ad3r.env"
if [ -d "/system/0vl0ad3r/bin" ]; then
    export PATH="/system/0vl0ad3r/bin:$PATH"
    export LD_LIBRARY_PATH="/system/0vl0ad3r/lib64:$LD_LIBRARY_PATH"
fi
EOF

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "base-layout" \
    "$BASE_LAYOUT_VER" \
    "1" \
    "$(manifest_desc base-layout)" \
    "https://github.com/LemonFan-maker/P4ck4g3s" \
    "Apache-2.0"

log_success "base-layout构建与打包完成!"
