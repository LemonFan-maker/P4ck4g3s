#!/usr/bin/env bash
set -eo pipefail

_MANIFEST_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_QUERY="${MANIFEST_QUERY:-$_MANIFEST_SH_DIR/manifest-query.py}"

if [[ ! -f "$MANIFEST_QUERY" ]]; then
    echo -e "\033[1;31m[-] 找不到清单读取器:$MANIFEST_QUERY\033[0m"
    return 1 2>/dev/null || exit 1
fi

manifest_field() {
    "$MANIFEST_QUERY" "$1" "$2"
}

manifest_repo() { manifest_field "$1" repo; }
manifest_ref() { manifest_field "$1" ref; }
manifest_tar() { manifest_field "$1" tar; }
manifest_tar_url() { manifest_field "$1" tar_url; }
manifest_tar_fallback() { manifest_field "$1" tar_url_fallback; }
manifest_version() { manifest_field "$1" version; }
manifest_desc() { manifest_field "$1" desc; }
manifest_sha256() { manifest_field "$1" sha256; }
manifest_source() { manifest_field "$1" source; }

manifest_require_version() {
    local pkg="$1" version
    version="$(manifest_version "$pkg")" || {
        echo -e "\033[1;31m[-] 组件清单里没有$pkg,请运行./scripts/sync-archlinux.py\033[0m"
        return 1
    }
    if [[ -z "$version" ]]; then
        echo -e "\033[1;31m[-] $pkg在清单里没有版本号(见manifest/components.manifest)\033[0m"
        return 1
    fi
    printf '%s\n' "$version"
}

fetch_source() {
    local pkg="$1" src_dir="$2"
    local repo ref tar tar_url tar_fallback sha candidate

    if ! repo="$(manifest_repo "$pkg")" || [[ -z "$repo" ]]; then
        tar="$(manifest_tar "$pkg")" || true
        if [[ -z "$tar" ]]; then
            echo -e "\033[1;31m[-] 清单里$pkg既没有repo也没有tarball,无法取源\033[0m"
            return 1
        fi
        tar_url="$(manifest_tar_url "$pkg")"
        tar_fallback="$(manifest_tar_fallback "$pkg")"
        # 回退必须覆盖"传输成功但内容不对"这一档。镜像偶尔会返回一个完整的错误
        # 响应, curl 退出 0; 只按下载失败回退会漏掉它, 坏产物会一路走到 sha256
        # 门禁才失败, 白白浪费一次构建。
        sha="$(manifest_sha256 "$pkg")"
        local fetched=1
        for candidate in "$tar_url" "$tar_fallback"; do
            [[ -z "$candidate" ]] && continue
            if download_tarball "$candidate" "$tar" \
                && verify_sha256 "$DOWNLOADS_DIR/$tar" "$sha" "$pkg"; then
                fetched=0
                break
            fi
            # 该源不可信, 丢弃其产物; 否则下一个源会命中"缓存已存在"而不再重取,
            # 于是坏文件被当成好文件继续用。
            rm -f "$DOWNLOADS_DIR/$tar"
        done
        if [[ "$fetched" -ne 0 ]]; then
            echo -e "\033[1;31m[-] $pkg的tarball在$tar_url与$tar_fallback均未通过sha256\033[0m"
            return 1
        fi
        rm -rf "$src_dir"
        mkdir -p "$src_dir"
        tar -xf "$DOWNLOADS_DIR/$tar" --strip-components=1 -C "$src_dir"
        return 0
    fi

    ref="$(manifest_ref "$pkg")"
    if [[ -z "$ref" ]]; then
        echo -e "\033[1;31m[-] 清单里$pkg有repo但没有ref,拒绝跟分支构建\033[0m"
        return 1
    fi
    git_clone_latest "$repo" "$src_dir" "$ref"
}
