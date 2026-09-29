#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/bootstrap/env.sh"

log_info "开始执行0vl0ad3r常用工具链全量构建流程"
log_info "目标平台:Android API ${ANDROID_API}(aarch64)"
log_info "目标组件:ncurses, curl, wget, aria2, nano, vim, vi"

SECONDS=0

log_info ">>> [阶段1/6] 正在构建基础依赖库(zlib, zstd, xz, openssl, libarchive, libcurl, ncurses, pacman)..."
"$REPO_ROOT/bootstrap/build-zlib.sh"
"$REPO_ROOT/bootstrap/build-zstd.sh"
"$REPO_ROOT/bootstrap/build-xz.sh"
"$REPO_ROOT/bootstrap/build-openssl.sh"
"$REPO_ROOT/bootstrap/build-curl.sh"
"$REPO_ROOT/bootstrap/build-archive.sh"
"$REPO_ROOT/bootstrap/build-ncurses.sh"
"$REPO_ROOT/bootstrap/build-pacman.sh"

log_info ">>> [阶段2/6] 正在切分底层共享库(zlib, zstd, xz, openssl, libarchive, libcurl)..."
"$SCRIPT_DIR/build-libs.sh"

log_info ">>> [阶段3/6] 正在构建基础布局与证书链(base-layout, ca-certificates)..."
"$SCRIPT_DIR/build-base-layout.sh"
"$SCRIPT_DIR/build-ca-certificates.sh"

log_info ">>> [阶段4/6] 正在封装pacman自举包..."
"$SCRIPT_DIR/build-bootstrap-package.sh"

log_info ">>> [阶段5/6] 正在构建应用工具集(curl, wget, aria2, nano, vim, vi)..."
"$SCRIPT_DIR/build-curl.sh"
"$SCRIPT_DIR/build-wget.sh"
"$SCRIPT_DIR/build-aria2.sh"
"$SCRIPT_DIR/build-nano.sh"
"$SCRIPT_DIR/build-vim.sh"
"$SCRIPT_DIR/build-vi.sh"

log_info ">>> [阶段6/6] 正在更新软件源数据库索引并校验最终产物..."
"$SCRIPT_DIR/update-repo.sh"
"$SCRIPT_DIR/verify-packages.sh"

log_info ">>> 正在装配客户端引导种子镜像(0vl0ad3r-bootstrap-aarch64.tar.zst)..."
"$REPO_ROOT/bootstrap/package-bootstrap.sh"

ELAPSED=$SECONDS
log_success "全量构建与软件源更新完成!总耗时:${ELAPSED}秒"
log_success "生成的包软件包清单位于output/repo/:"
ls -lh "$REPO_ROOT/output/repo"/*.pkg.tar.zst
