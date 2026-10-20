#!/usr/bin/env bash
ensure_ca_bundle() {
    local name url expected

    name="$(manifest_tar ca-certificates)"
    url="$(manifest_tar_url ca-certificates)"
    expected="$(manifest_sha256 ca-certificates)"

    if [[ -z "$name" || -z "$url" || -z "$expected" ]]; then
        log_error "清单里ca-certificates缺少文件名/下载地址/sha256,拒绝构建根证书集"
        return 1
    fi

    CA_BUNDLE_PATH="$BUILD_DIR/$name"
    if [[ -f "$CA_BUNDLE_PATH" ]] &&
        verify_sha256 "$CA_BUNDLE_PATH" "$expected" "ca-certificates"; then
        log_info "复用已缓存且校验通过的根证书集:$(basename "$CA_BUNDLE_PATH")"
        return 0
    fi

    rm -f "$CA_BUNDLE_PATH"
    log_info "正在下载根证书集:$url"
    if ! curl -fsSL --retry 3 -o "$CA_BUNDLE_PATH" "$url"; then
        log_error "根证书集下载失败:$url"
        return 1
    fi
    if ! verify_sha256 "$CA_BUNDLE_PATH" "$expected" "ca-certificates"; then
        log_error "根证书集sha256校验失败:$CA_BUNDLE_PATH"
        return 1
    fi
    log_success "根证书集校验通过"
}
