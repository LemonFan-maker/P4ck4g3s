#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"

LIB_SPECS=(
    "zlib|libz.so*||通用压缩库(DEFLATE实现的Bionic aarch64原生版)"
    "zstd|libzstd.so*||Zstandard快速无损压缩库(zstd CLI的底层实现,Bionic aarch64原生版)"
    "xz|liblzma.so*||LZMA2压缩与解压库(Bionic aarch64原生版)"
    "openssl|libssl.so* libcrypto.so*||OpenSSL 3密码学与TLS库(Bionic aarch64原生版)"
    "libarchive|libarchive.so*||多格式归档读写库tar/zip/cpio(Bionic aarch64原生版)"
    "libcurl|libcurl.so*||libcurl传输库HTTP/FTP/TLS(Bionic aarch64原生版)"
    "libc++|libc++_shared.so|NDK|LLVM libc++共享运行时库(来自Android NDK sysroot)"
    "libalpm|libalpm.so*||Arch Linux包管理器核心库libalpm(pacman的引擎)"
)

detect_version() {
    local name="$1"
    case "$name" in
        zlib) grep -oE 'ZLIB_TAG="v?[0-9.]+"' "$REPO_ROOT/bootstrap/build-zlib.sh" | grep -oE '[0-9.]+' ;;
        zstd) grep -oE 'ZSTD_TAG="v?[0-9.]+"' "$REPO_ROOT/bootstrap/build-zstd.sh" | grep -oE '[0-9.]+' ;;
        xz) grep -oE 'XZ_TAG="v?[0-9.]+"' "$REPO_ROOT/bootstrap/build-xz.sh" | grep -oE '[0-9.]+' ;;
        libarchive) grep -oE 'ARCHIVE_TAG="v?[0-9.]+"' "$REPO_ROOT/bootstrap/build-archive.sh" | grep -oE '[0-9.]+' ;;
        openssl) sed -n 's/.*OPENSSL_VERSION_STR *"\([0-9.]*\)".*/\1/p' "$SYSROOT/include/openssl/opensslv.h" 2>/dev/null ;;
        libcurl) sed -n 's/.*LIBCURL_VERSION *"\([0-9][0-9.]*\).*/\1/p' "$SYSROOT/include/curl/curlver.h" 2>/dev/null ;;
        libalpm) grep -oE 'PACMAN_TAG="v?[0-9.]+"' "$REPO_ROOT/bootstrap/build-pacman.sh" | grep -oE '[0-9.]+' ;;
        libc++) grep -m1 '^# *define _LIBCPP_VERSION' \
                    "$NDK_TOOLCHAIN/sysroot/usr/include/c++/v1/__config" 2>/dev/null \
                    | awk '{printf "%d.%d.%d", int($4/10000), int($4/100)%100, $4%100}' ;;
    esac
}

if [[ $# -gt 0 ]]; then
    SELECTED=("$@")
else
    SELECTED=()
    for spec in "${LIB_SPECS[@]}"; do SELECTED+=("${spec%%|*}"); done
fi

log_info "开始切分底层共享库为可更新的包软件包"
log_info "目标前缀:${TARGET_PREFIX}(aarch64)"
log_info "待处理库:${SELECTED[*]}"

BUILT=()
for spec in "${LIB_SPECS[@]}"; do
    IFS='|' read -r pkgname so_patterns source_kind description <<< "$spec"

    if ! printf '%s\n' "${SELECTED[@]}" | grep -qx "$pkgname"; then
        continue
    fi

    STAGE="$BUILD_DIR/stage_lib_$pkgname"
    rm -rf "$STAGE"
    mkdir -p "$STAGE/lib64"

    COLLECTED=0
    if [[ "$source_kind" == "NDK" ]]; then
        NDK_LIBDIR="$NDK_TOOLCHAIN/sysroot/usr/lib/$TARGET_TRIPLE"
        for pattern in $so_patterns; do
            while IFS= read -r -d '' libfile; do
                cp -P "$libfile" "$STAGE/lib64/" 2>/dev/null && COLLECTED=$((COLLECTED + 1))
            done < <(find "$NDK_LIBDIR" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
        done
    else
        for pattern in $so_patterns; do
            while IFS= read -r -d '' libfile; do
                cp -P "$libfile" "$STAGE/lib64/" 2>/dev/null && COLLECTED=$((COLLECTED + 1))
            done < <(find "$SYSROOT/lib64" "$SYSROOT/lib" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
        done
    fi

    if [[ $COLLECTED -eq 0 ]]; then
        log_error "库${pkgname}在SYSROOT中未找到任何匹配文件(${so_patterns}),跳过"
        log_error "请先执行./bootstrap/build-all.sh生成sysroot"
        continue
    fi

    VERSION="$(detect_version "$pkgname")"
    if [[ -z "$VERSION" ]]; then
        log_error "无法探测${pkgname}版本号,跳过"
        continue
    fi

    if [[ -z "$description" ]]; then
        log_error "库包${pkgname}缺少描述,拒绝打包(index.json会把它变成null,前端只能显示空白卡片)"
        exit 1
    fi

    log_info ">>> 封装库包${pkgname}-${VERSION}(${COLLECTED}个库文件)..."

    "$REPO_ROOT/scripts/pack-pkg.sh" \
        "$STAGE" \
        "$pkgname" \
        "$VERSION" \
        "1" \
        "$description" \
        "https://0vl0ad3r.org/packages/$pkgname" \
        "custom"

    BUILT+=("$pkgname-$VERSION-1-aarch64.pkg.tar.zst")
done

if [[ ${#BUILT[@]} -eq 0 ]]; then
    log_error "未成功构建任何库包,请检查上方错误"
    exit 1
fi

log_success "库包切分完成,共${#BUILT[@]}个:"
for b in "${BUILT[@]}"; do log_success "output/repo/${b}"; done
log_success "这些包安装后由pacman拥有,可用pacman -U原地更新"
