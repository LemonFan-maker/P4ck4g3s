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

export CC="$NDK_TOOLCHAIN/bin/${TARGET_TRIPLE}${ANDROID_API}-clang"
export CXX="$NDK_TOOLCHAIN/bin/${TARGET_TRIPLE}${ANDROID_API}-clang++"
export AR="$NDK_TOOLCHAIN/bin/llvm-ar"
export AS="$CC"
export LD="$NDK_TOOLCHAIN/bin/ld.lld"
export RANLIB="$NDK_TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$NDK_TOOLCHAIN/bin/llvm-strip"
export OBJCOPY="$NDK_TOOLCHAIN/bin/llvm-objcopy"
export READELF="$NDK_TOOLCHAIN/bin/llvm-readelf"

export CFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I$SYSROOT/include"
export CXXFLAGS="-O2 -pipe -fPIC -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I$SYSROOT/include"
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
    else
        log_info "正在下载:$url -> $dest_filename"
        curl -fSL "$url" -o "$target_path"
        log_success "下载完成:$dest_filename"
    fi
}

git_clone_latest() {
    local repo_url="$1"
    local dest_dir="$2"
    local branch_or_tag="${3:-}"

    if [[ -d "$dest_dir/.git" ]]; then
        log_info "更新本地Git仓库:$(basename "$dest_dir") -> ${branch_or_tag:-default}"
        if [[ -n "$branch_or_tag" ]]; then
            git -C "$dest_dir" fetch --depth 1 origin "$branch_or_tag"
        else
            git -C "$dest_dir" fetch --depth 1 origin HEAD
        fi
        git -C "$dest_dir" checkout -f FETCH_HEAD
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

git_pkgver() {
    local src_dir="$1"
    local base_ver="$2"
    local commit exact_tag

    if [[ -z "$base_ver" ]]; then
        log_error "git_pkgver:未提供上游基础版本号,拒绝生成pkgver"
        return 1
    fi

    if [[ ! -d "$src_dir/.git" ]]; then
        printf '%s\n' "$base_ver"
        return 0
    fi

    exact_tag="$(git -C "$src_dir" tag --points-at HEAD 2>/dev/null | head -1 || true)"
    if [[ -n "$exact_tag" ]]; then
        printf '%s\n' "$base_ver"
        return 0
    fi

    commit="$(git -C "$src_dir" rev-parse --short HEAD 2>/dev/null || true)"
    if [[ -z "$commit" ]]; then
        log_error "无法从$src_dir取得commit,拒绝生成pkgver"
        log_error "版本号必须能唯一标识构建,否则客户端永远拿不到新构建"
        return 1
    fi

    printf '%s.%s.g%s\n' "$base_ver" "$(date -u +%Y%m%d%H%M%S)" "$commit"
}

apply_patches() {
    local component="$1"
    local target_dir="$2"
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
        if patch -d "$target_dir" -p1 -N --dry-run --silent < "$patch_file" >/dev/null 2>&1; then
            patch -d "$target_dir" -p1 < "$patch_file"
            log_success "已成功应用补丁:${patch_name}"
        elif patch -d "$target_dir" -p1 -R --dry-run --silent < "$patch_file" >/dev/null 2>&1; then
            log_info "补丁此前已应用,跳过:${patch_name}"
        else
            log_error "应用补丁失败:${patch_name}"
            patch -d "$target_dir" -p1 < "$patch_file" || exit 1
        fi
    done
}
