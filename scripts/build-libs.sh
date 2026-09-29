#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"
source "$SCRIPT_DIR/manifest.sh"

LIB_SPECS=(
    "zlib|libz.so*|"
    "zstd|libzstd.so*|"
    "xz|liblzma.so*|"
    "openssl|libssl.so* libcrypto.so*|"
    "libarchive|libarchive.so*|"
    "libcurl|libcurl.so*|"
    "libc++|libc++_shared.so|NDK"
    "libalpm|libalpm.so*|"
)

measure_version() {
    case "$1" in
        zlib)
            sed -n 's/^#define[[:space:]][[:space:]]*ZLIB_VERSION[[:space:]][[:space:]]*"\([^"]*\)".*/\1/p' \
                "$SYSROOT/include/zlib.h" 2>/dev/null | head -1 ;;
        zstd)
            awk '/^#define ZSTD_VERSION_MAJOR/{a=$3}
                 /^#define ZSTD_VERSION_MINOR/{b=$3}
                 /^#define ZSTD_VERSION_RELEASE/{c=$3}
                 END{printf "%s.%s.%s", a, b, c}' \
                "$SYSROOT/include/zstd.h" 2>/dev/null ;;
        xz)
            awk '/^#define LZMA_VERSION_MAJOR/{a=$3}
                 /^#define LZMA_VERSION_MINOR/{b=$3}
                 /^#define LZMA_VERSION_PATCH/{c=$3}
                 END{printf "%s.%s.%s", a, b, c}' \
                "$SYSROOT/include/lzma/version.h" 2>/dev/null ;;
        openssl)
            sed -n 's/^#[[:space:]]*define[[:space:]][[:space:]]*OPENSSL_VERSION_STR[[:space:]][[:space:]]*"\([^"]*\)".*/\1/p' \
                "$SYSROOT/include/openssl/opensslv.h" 2>/dev/null | head -1 ;;
        libarchive)
            sed -n 's/^#define[[:space:]][[:space:]]*ARCHIVE_VERSION_ONLY_STRING[[:space:]][[:space:]]*"\([^"]*\)".*/\1/p' \
                "$SYSROOT/include/archive.h" 2>/dev/null | head -1 ;;
        libcurl)
            sed -n 's/^#define[[:space:]][[:space:]]*LIBCURL_VERSION[[:space:]][[:space:]]*"\([^"]*\)".*/\1/p' \
                "$SYSROOT/include/curl/curlver.h" 2>/dev/null | head -1 | sed 's/-DEV$//' ;;
        libc++)
            grep -m1 '^# *define _LIBCPP_VERSION' \
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
    IFS='|' read -r pkgname so_patterns source_kind <<< "$spec"

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

    VERSION="$(manifest_require_version "$pkgname")"
    MEASURED="$(measure_version "$pkgname")"
    if [[ -z "$MEASURED" ]]; then
        log_info "$pkgname头文件无可实测的版本标记,以清单为准:${VERSION}"
    elif [[ "$MEASURED" != "$VERSION" ]]; then
        if [[ "$source_kind" == "NDK" ]]; then
            log_error "libc++版本与清单不符:NDK实测$MEASURED,清单期望$VERSION"
            log_error "当前工具链不是清单钉住的那一颗,产物会与CI不一致"
            log_error "换回钉住的NDK,或更新sync-archlinux.py中libc++/ndk版本后重新生成清单"
        else
            log_error "${pkgname}版本与清单不符:sysroot实测$MEASURED,清单$VERSION"
            log_error "sysroot里是上一轮构建的旧库,直接切包会给旧库贴上新版本号"
            log_error "请重新构建对应组件,或运行./scripts/sync-archlinux.py刷新清单"
        fi
        exit 1
    fi

    description="$(manifest_desc "$pkgname")"
    if [[ -z "$description" ]]; then
        log_error "库包${pkgname}缺少描述,拒绝打包(index.json会把它变成null,前端只能显示空白卡片)"
        log_error "请运行./scripts/sync-archlinux.py刷新清单,或在脚本内补上该包描述"
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
