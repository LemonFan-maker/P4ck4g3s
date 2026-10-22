#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"
source "$SCRIPT_DIR/ca-bundle.sh"

BASE_LAYOUT_VER="$(manifest_require_version base-layout)"
# pkgver 跟随语义版本; 只改打包内容(配置文件、目录布局)时递增 pkgrel。
BASE_LAYOUT_REL="3"
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
export PATH="$PREFIX/bin:/system/bin:/system/xbin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="$PREFIX/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export HOME="${HOME:-/data/local/tmp}"
export TMPDIR="${TMPDIR:-/data/local/tmp}"
export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-C.UTF-8}"

if [ -r "$PREFIX/etc/0vl0ad3r.env" ]; then
    . "$PREFIX/etc/0vl0ad3r.env"
fi

run_shell() {
    shell="$1"
    shift
    export SHELL="$PREFIX/bin/$shell"
    case "$shell" in
        bash)
            exec "$PREFIX/bin/bash" --rcfile "$PREFIX/etc/bash.bashrc" -i "$@"
            ;;
        zsh)
            exec "$PREFIX/bin/zsh" -i "$@"
            ;;
        fish)
            exec "$PREFIX/bin/fish" -i "$@"
            ;;
        *)
            exec /system/bin/sh
            ;;
    esac
}

case "$1" in
    sh|shell)
        export SHELL="/system/bin/sh"
        exec /system/bin/sh
        ;;
    bash|zsh|fish)
        run_shell "$@"
        ;;
    exec)
        shift
        exec "$@"
        ;;
    "")
        if [ -x "$PREFIX/bin/bash" ]; then
            run_shell bash
        elif [ -x "$PREFIX/bin/zsh" ]; then
            run_shell zsh
        elif [ -x "$PREFIX/bin/fish" ]; then
            run_shell fish
        else
            export SHELL="/system/bin/sh"
            exec /system/bin/sh
        fi
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

# 本底座的 pacman 以 -Dgpgme=disabled 编译, 没有签名能力。
# 这里必须写 Never; Optional/Required 会让 pacman 报
# "SigLevel option invalid, no signature support" 并拒绝启动。
SigLevel = Never
LocalFileSigLevel = Never

Color
CheckSpace
VerbosePkgLists
ILoveCandy

[0vl0ad3r]
Include = /system/0vl0ad3r/etc/pacman.d/mirrorlist
EOF

check_pacman_conf_has_no_signature_requirements "$STAGING_DIR/etc/pacman.conf"

cat <<EOF > "$STAGING_DIR/etc/pacman.d/mirrorlist"
Server = $MIRROR_PRIMARY
EOF

cat <<'EOF' > "$STAGING_DIR/etc/0vl0ad3r.env"
# POSIX sh环境入口,供bash/zsh、0vl和终端APK共同使用。
export PREFIX="/system/0vl0ad3r"
export PATH="$PREFIX/bin:/system/bin:/system/xbin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="$PREFIX/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export HOME="${HOME:-/data/local/tmp}"
export TMPDIR="${TMPDIR:-/data/local/tmp}"
export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-C.UTF-8}"
EOF

"$REPO_ROOT/scripts/pack-pkg.sh" \
    "$STAGING_DIR" \
    "base-layout" \
    "$BASE_LAYOUT_VER" \
    "$BASE_LAYOUT_REL" \
    "$(manifest_desc base-layout)" \
    "https://github.com/LemonFan-maker/P4ck4g3s" \
    "Apache-2.0"

log_success "base-layout构建与打包完成!"
