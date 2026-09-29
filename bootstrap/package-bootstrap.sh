#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

STAGE_DIR="$BUILD_DIR/bootstrap_stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/lib64" "$STAGE_DIR/etc/pacman.d" "$STAGE_DIR/etc/ssl/certs"
mkdir -p "$STAGE_DIR/var/lib/pacman/local" "$STAGE_DIR/var/cache/pacman/pkg" "$STAGE_DIR/var/log"
mkdir -p "$STAGE_DIR/tmp" "$STAGE_DIR/share"

log_info ">>> 正在收集自举二进制与库文件..."

for bin in pacman pacman-conf zstd zstdcat unzstd xz lzmadec curl; do
    if [[ -f "$SYSROOT/bin/$bin" ]]; then
        cp -a "$SYSROOT/bin/$bin" "$STAGE_DIR/bin/"
        "$STRIP" --strip-unneeded "$STAGE_DIR/bin/$bin" 2>/dev/null || true
    fi
done

for lib_pattern in "libz.so*" "libzstd.so*" "liblzma.so*" "libcrypto.so*" "libssl.so*" "libcurl.so*" "libarchive.so*" "libalpm.so*"; do
    find "$SYSROOT/lib" "$SYSROOT/lib64" -maxdepth 1 -name "$lib_pattern" -exec cp -a {} "$STAGE_DIR/lib64/" \; 2>/dev/null || true
done

find "$STAGE_DIR/lib64" -type f -name "*.so*" -exec "$STRIP" --strip-unneeded {} \; 2>/dev/null || true

if command -v patchelf >/dev/null 2>&1; then
    for elf in "$STAGE_DIR/bin"/* "$STAGE_DIR/lib64"/*.so*; do
        if [[ -f "$elf" ]] && file "$elf" | grep -q "ELF"; then
            patchelf --set-rpath '$ORIGIN/../lib64' "$elf" 2>/dev/null || true
        fi
    done
fi

cat <<'EOF' > "$STAGE_DIR/etc/pacman.conf"
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

[0vl0ad3r-core]
Include = /system/0vl0ad3r/etc/pacman.d/mirrorlist
EOF

cat <<'EOF' > "$STAGE_DIR/etc/pacman.d/mirrorlist"
Server = https://lemonfan-maker.github.io/P4ck4g3s
Server = https://github.com/LemonFan-maker/P4ck4g3s/releases/latest/download
EOF

cat <<'EOF' > "$STAGE_DIR/bin/0vl"
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
chmod +x "$STAGE_DIR/bin/0vl"

cat <<'EOF' > "$STAGE_DIR/etc/0vl0ad3r.env"
if [ -d "/system/0vl0ad3r/bin" ]; then
    export PATH="/system/0vl0ad3r/bin:$PATH"
    export LD_LIBRARY_PATH="/system/0vl0ad3r/lib64:$LD_LIBRARY_PATH"
fi
EOF

log_info "正在生成whiteout底座清单文件..."
cd "$STAGE_DIR"
find . -mindepth 1 -not -type d | sed 's|^\./||' | sort > whiteout
log_success "whiteout清单生成成功,共包含$(wc -l < whiteout)个底座文件条目"

OUTPUT_TARBALL="$OUTPUT_DIR/0vl0ad3r-bootstrap-aarch64.tar.zst"
log_info "正在打包自举文件至:$OUTPUT_TARBALL..."
tar -cf - . | zstd -19 -f -T"$(nproc)" -o "$OUTPUT_TARBALL"

log_success "自举底座打包成功!"
log_info "文件大小:$(du -h "$OUTPUT_TARBALL" | cut -f1)"
log_info "文件路径:$OUTPUT_TARBALL"
