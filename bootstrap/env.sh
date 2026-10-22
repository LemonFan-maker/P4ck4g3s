#!/usr/bin/env bash
set -eo pipefail

export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-/opt/android-ndk}"
if [[ ! -d "$ANDROID_NDK_ROOT" ]]; then
    echo "[-] 错误:未找到Android NDK目录:$ANDROID_NDK_ROOT"
    echo "请设置ANDROID_NDK_ROOT环境变量,例如:export ANDROID_NDK_ROOT=/opt/android-ndk"
    exit 1
fi

_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT="$(cd "$_ENV_DIR/.." && pwd)"
unset _ENV_DIR
export BUILD_DIR="$REPO_ROOT/build"
export DOWNLOADS_DIR="$REPO_ROOT/downloads"
export SYSROOT="$BUILD_DIR/sysroot"
export TARGET_PREFIX="/system/0vl0ad3r"
export OUTPUT_DIR="$REPO_ROOT/output/bootstrap"
export PATCHES_DIR="$REPO_ROOT/patches"

mkdir -p "$BUILD_DIR" "$DOWNLOADS_DIR" "$SYSROOT" "$OUTPUT_DIR" "$PATCHES_DIR"
mkdir -p "$SYSROOT/bin" "$SYSROOT/lib64" "$SYSROOT/include" "$SYSROOT/etc" "$SYSROOT/share"

export ANDROID_API=33
export TARGET_ARCH=aarch64
export TARGET_TRIPLE="aarch64-linux-android"
export NDK_TOOLCHAIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"

NDK_PINNED="$(python3 "$REPO_ROOT/scripts/manifest-query.py" ndk version 2>/dev/null || true)"
if [[ -n "$NDK_PINNED" ]]; then
    NDK_ACTUAL="$(sed -n 's/^Pkg.ReleaseName *= *//p' "$ANDROID_NDK_ROOT/source.properties" 2>/dev/null)"
    if [[ -z "$NDK_ACTUAL" ]]; then
        NDK_ACTUAL="未知(读不到source.properties)"
    fi
    if [[ "$NDK_ACTUAL" != "$NDK_PINNED" ]]; then
        if [[ -n "${ALLOW_NDK_MISMATCH:-}" ]]; then
            echo -e "\033[1;33m[!] NDK版本与清单不符:实际$NDK_ACTUAL,清单钉$NDK_PINNED"
            echo -e "    已按ALLOW_NDK_MISMATCH继续,但libc++产物可能与CI不一致\033[0m"
        else
            echo -e "\033[1;31m[-] NDK版本与清单不符:实际$NDK_ACTUAL,清单钉$NDK_PINNED"
            echo -e "    libc++的版本由NDK决定,换工具链会静默产出不同的包"
            echo -e "    请把ANDROID_NDK_ROOT指向$NDK_PINNED,"
            echo -e "    或更新scripts/sync-archlinux.py中ndk/libc++的版本后重新生成清单"
            echo -e "    确要用当前NDK(产物可能与CI不一致):先export ALLOW_NDK_MISMATCH=1再重新构建\033[0m"
            exit 1
        fi
    fi
fi

export CC="$NDK_TOOLCHAIN/bin/${TARGET_TRIPLE}${ANDROID_API}-clang"
export CXX="$NDK_TOOLCHAIN/bin/${TARGET_TRIPLE}${ANDROID_API}-clang++"
export AR="$NDK_TOOLCHAIN/bin/llvm-ar"
export AS="$CC"
export LD="$NDK_TOOLCHAIN/bin/ld.lld"
export RANLIB="$NDK_TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$NDK_TOOLCHAIN/bin/llvm-strip"
export OBJCOPY="$NDK_TOOLCHAIN/bin/llvm-objcopy"
export READELF="$NDK_TOOLCHAIN/bin/llvm-readelf"

export CFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -I$SYSROOT/include"
export CXXFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -I$SYSROOT/include"
export LDFLAGS="-L$SYSROOT/lib -L$SYSROOT/lib64 -Wl,-rpath,'\$ORIGIN/../lib64' -Wl,--enable-new-dtags"
export CPPFLAGS="-I$SYSROOT/include"
export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig:$SYSROOT/lib64/pkgconfig:$SYSROOT/share/pkgconfig"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"

export MAKEFLAGS="-j$(nproc)"
export CMAKE_BUILD_PARALLEL_LEVEL="$(nproc)"

export CMAKE_TOOLCHAIN_FILE="$BUILD_DIR/android_toolchain.cmake"
cat <<EOF > "$CMAKE_TOOLCHAIN_FILE"
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "Minimum policy version")
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION $ANDROID_API)
set(ANDROID_PLATFORM_LEVEL $ANDROID_API)
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)
set(CMAKE_ANDROID_NDK "$ANDROID_NDK_ROOT")
set(CMAKE_C_COMPILER "$CC")
set(CMAKE_CXX_COMPILER "$CXX")
set(CMAKE_AR "$AR" CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB "$RANLIB" CACHE FILEPATH "Ranlib")
set(CMAKE_STRIP "$STRIP" CACHE FILEPATH "Strip")
set(CMAKE_SYSROOT "$NDK_TOOLCHAIN/sysroot")
set(CMAKE_FIND_ROOT_PATH "$SYSROOT" "$NDK_TOOLCHAIN/sysroot")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_INSTALL_PREFIX "$SYSROOT")
set(CMAKE_C_FLAGS_INIT "$CFLAGS")
set(CMAKE_CXX_FLAGS_INIT "$CXXFLAGS")
set(CMAKE_EXE_LINKER_FLAGS_INIT "$LDFLAGS")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "$LDFLAGS")
EOF

export MESON_CROSS_FILE="$BUILD_DIR/meson_cross.txt"
cat <<EOF > "$MESON_CROSS_FILE"
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkg-config = '/usr/bin/pkg-config'

[built-in options]
c_args = ['-O2', '-pipe', '-fPIC', '-D_FILE_OFFSET_BITS=64', '-D_GNU_SOURCE', '-I$SYSROOT/include']
cpp_args = ['-O2', '-pipe', '-fPIC', '-D_FILE_OFFSET_BITS=64', '-D_GNU_SOURCE', '-I$SYSROOT/include']
c_link_args = ['-L$SYSROOT/lib', '-L$SYSROOT/lib64', '-Wl,-rpath,\$ORIGIN/../lib64', '-Wl,--enable-new-dtags']
cpp_link_args = ['-L$SYSROOT/lib', '-L$SYSROOT/lib64', '-Wl,-rpath,\$ORIGIN/../lib64', '-Wl,--enable-new-dtags']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'
EOF

log_info() {
    echo -e "\033[1;34m[*] $1\033[0m"
}

log_success() {
    echo -e "\033[1;32m[+] $1\033[0m"
}

log_error() {
    echo -e "\033[1;31m[-] $1\033[0m"
}

download_tarball() {
    local url="$1"
    local dest_filename="$2"
    local target_path="$DOWNLOADS_DIR/$dest_filename"

    if [[ -f "$target_path" ]]; then
        log_info "缓存已存在:$dest_filename"
        return 0
    fi

    log_info "正在下载:$url -> $dest_filename"
    # 本函数总在 || / if 条件里被调用, set -e 对条件上下文中的函数不生效,
    # 因此必须显式传递 curl 的状态。早先以 log_success 收尾, 恒返回 0,
    # "下载失败就换回退源"那条分支从来没被走到过。
    # --remove-on-error: 传输中断时不把半截文件留在缓存里, 否则下次会命中
    # "缓存已存在"直接拿它去解压, 把一次网络抖动变成确定的构建失败。
    if ! curl -fSL --retry 3 --retry-all-errors --remove-on-error "$url" -o "$target_path"; then
        log_error "下载失败:$url"
        return 1
    fi
    log_success "下载完成:$dest_filename"
    return 0
}

verify_sha256() {
    local path="$1" expected="$2" name="${3:-$(basename "$1")}"

    if [[ -z "$expected" ]]; then
        return 0
    fi
    if [[ ! -f "$path" ]]; then
        log_error "$name校验失败:文件不存在$path"
        return 1
    fi

    local actual
    actual="$(sha256sum "$path" | cut -d' ' -f1)"
    if [[ "$actual" != "$expected" ]]; then
        log_error "$name的sha256与清单不符"
        log_error "  期望:$expected"
        log_error "  实际:$actual"
        log_error "  文件:$path"
        log_error "若是上游确实换了产物,请更新scripts/sync-archlinux.py里的校验值后重新生成清单"
        return 1
    fi
    log_info "$name sha256校验通过"
}

git_clone_latest() {
    local repo_url="$1"
    local dest_dir="$2"
    local branch_or_tag="${3:-}"

    if [[ -d "$dest_dir/.git" ]]; then
        log_info "更新本地Git仓库:$(basename "$dest_dir") -> ${branch_or_tag:-default}"
        if [[ -n "$branch_or_tag" ]]; then
            git -C "$dest_dir" fetch --depth 1 origin \
                "refs/tags/$branch_or_tag:refs/tags/$branch_or_tag" 2>/dev/null \
                || git -C "$dest_dir" fetch --depth 1 origin "$branch_or_tag"
            if git -C "$dest_dir" rev-parse -q --verify "refs/tags/$branch_or_tag" >/dev/null; then
                git -C "$dest_dir" checkout -f "refs/tags/$branch_or_tag"
            else
                git -C "$dest_dir" checkout -f FETCH_HEAD
            fi
        else
            git -C "$dest_dir" fetch --depth 1 origin HEAD
            git -C "$dest_dir" checkout -f FETCH_HEAD
        fi
        log_info "已检出:$(git -C "$dest_dir" rev-parse --short HEAD)"
    else
        log_info "正在从源码仓库克隆最新代码:$repo_url(版本/标签:${branch_or_tag:-default})..."
        rm -rf "$dest_dir"
        if [[ -n "$branch_or_tag" ]]; then
            git clone --depth 1 --branch "$branch_or_tag" "$repo_url" "$dest_dir"
        else
            git clone --depth 1 "$repo_url" "$dest_dir"
        fi
        if [[ ! -d "$dest_dir/.git" ]]; then
            log_error "git clone未产出有效检出($dest_dir/.git不存在),视为失败以触发回退"
            return 1
        fi
        log_success "代码拉取完成:$(basename "$dest_dir")"
    fi
}

check_pacman_conf_has_no_signature_requirements() {
    local conf="$1"
    if grep -Eq '^[[:space:]]*(SigLevel|LocalFileSigLevel|RemoteFileSigLevel)[[:space:]]*=.*(Optional|Required)' "$conf"; then
        log_error "pacman 以 -Dgpgme=disabled 编译, 配置不能启用签名校验: $conf"
        log_error "请把 SigLevel / LocalFileSigLevel 设为 Never"
        return 1
    fi
}

apply_patches() {
    local component="$1"
    local target_dir="$2"
    local strip="${3:-1}"
    local comp_patch_dir="$PATCHES_DIR/$component"

    if [[ ! -d "$comp_patch_dir" ]]; then
        log_info "未检测到${component}补丁目录,跳过补丁应用"
        return 0
    fi

    shopt -s nullglob
    local patches=("$comp_patch_dir"/*.patch)
    shopt -u nullglob

    if [[ ${#patches[@]} -eq 0 ]]; then
        log_info "${component}补丁目录为空,跳过补丁应用"
        return 0
    fi

    log_info "正在为${component}应用补丁(目录:patches/${component})..."
    for patch_file in "${patches[@]}"; do
        local patch_name
        patch_name="$(basename "$patch_file")"
        if patch -d "$target_dir" -p"$strip" -N --dry-run --silent < "$patch_file" >/dev/null 2>&1; then
            patch -d "$target_dir" -p"$strip" < "$patch_file"
            log_success "已成功应用补丁:${patch_name}"
        elif patch -d "$target_dir" -p"$strip" -R --dry-run --silent < "$patch_file" >/dev/null 2>&1; then
            log_info "补丁此前已应用,跳过:${patch_name}"
        else
            log_error "应用补丁失败:${patch_name}"
            patch -d "$target_dir" -p"$strip" < "$patch_file" || exit 1
        fi
    done
}
