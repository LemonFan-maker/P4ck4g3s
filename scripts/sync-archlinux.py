#!/usr/bin/env python3
"""从Arch Linux官方软件源同步组件版本号与描述,生成manifest/components.manifest(CSV)。"""

import argparse
import csv
import io
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "manifest" / "components.manifest"
ARCH_API = "https://archlinux.org/packages/search/json/?name={}"
HTTP_TIMEOUT = 30
HTTP_ATTEMPTS = 3
HTTP_BACKOFF = 3

COMPONENTS = [
    dict(pkg="zlib", kind="lib", arch="zlib", ref="v{ver}", url=None, desc=None),
    dict(pkg="zstd", kind="lib", arch="zstd", ref="v{ver}", url=None, desc=None),
    dict(pkg="xz", kind="lib", arch="xz", ref="v{ver}", url=None, desc=None),
    dict(pkg="openssl", kind="lib", arch="openssl", ref="openssl-{ver}", url=None, desc=None),
    dict(pkg="libarchive", kind="lib", arch="libarchive", ref="v{ver}", url=None, desc=None),
    dict(pkg="libcurl", kind="lib", arch="curl", version_of="curl", ref="curl-{ver_curl}", url=None,
         desc="libcurl传输库HTTP/FTP/TLS"),
    dict(pkg="curl", kind="tool", arch="curl", ref="curl-{ver_curl}", url=None, desc=None),
    dict(pkg="libc++", kind="lib", source="derived", version="21.0.0",
         arch=None, version_of=None, ref=None, url=None,
         desc="LLVM libc++共享运行时库"),
    dict(pkg="libalpm", kind="lib", arch="pacman", version_of="pacman", ref="v{ver}", url=None,
         desc="Arch Linux包管理器核心库libalpm"),
    dict(pkg="pacman", kind="tool", arch="pacman", ref="v{ver}", url=None, desc=None),
    dict(pkg="ncurses", kind="tool", arch="ncurses", ref=None, url=None, desc=None,
         sha256={"6.6": "355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11"}),
    dict(pkg="nano", kind="tool", arch="nano", ref=None, url=None, desc=None,
         sha256={"9.2": "05ecb99247b782e8a5b3a25ed4101dd034b0236902f7449bc9795b717642f7e9"}),
    dict(pkg="vim", kind="tool", arch="vim", ref="v{ver}", url=None, desc=None),
    dict(pkg="vi", kind="tool", arch=None, version_of="vim", ref=None, url=None,
         desc="Vi文本编辑器接口"),
    dict(pkg="wget", kind="tool", arch="wget", ref=None, url=None, desc=None,
         sha256={"1.25.0": "766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784"}),
    dict(pkg="aria2", kind="tool", arch="aria2", ref="release-{ver}", url=None, desc=None),
    dict(pkg="ca-certificates", kind="data", source="pin", version="2024.09.24",
         sha256="189d3cf6d103185fba06d76c1af915263c6d42225481a1759e853b33ac857540",
         arch="ca-certificates", ref=None, url=None, desc=None),
    dict(pkg="base-layout", kind="data", source="pin", version="1.0.0",
         arch=None, version_of=None, ref=None, url=None,
         desc="0vl0ad3r基础文件系统层次结构与环境分流配置"),
    dict(pkg="ndk", kind="toolchain", source="pin", version="r30",
         arch=None, version_of=None, ref=None, url=None,
         desc="Android NDK交叉工具链(构建输入,不作为软件包发布)"),
]

REPOS = {
    "zlib": "https://github.com/madler/zlib.git",
    "zstd": "https://github.com/facebook/zstd.git",
    "xz": "https://github.com/tukaani-project/xz.git",
    "openssl": "https://github.com/openssl/openssl.git",
    "libarchive": "https://github.com/libarchive/libarchive.git",
    "curl": "https://github.com/curl/curl.git",
    "pacman": "https://gitlab.archlinux.org/pacman/pacman.git",
    "vim": "https://github.com/vim/vim.git",
    "aria2": "https://github.com/aria2/aria2.git",
}

TARBALLS = {
    "ncurses": ("ncurses-{ver}.tar.gz",
                "https://invisible-mirror.net/archives/ncurses/ncurses-{ver}.tar.gz",
                "https://ftp.gnu.org/gnu/ncurses/ncurses-{ver}.tar.gz"),
    "nano": ("nano-{ver}.tar.xz",
             "https://www.nano-editor.org/dist/v{maj}/nano-{ver}.tar.xz",
             "https://ftp.gnu.org/gnu/nano/nano-{ver}.tar.xz"),
    "wget": ("wget-{ver}.tar.gz",
             "https://ftp.gnu.org/gnu/wget/wget-{ver}.tar.gz",
             "https://mirrors.kernel.org/gnu/wget/wget-{ver}.tar.gz"),
    "ca-certificates": ("cacert-{ver_dashed}.pem",
                        "https://curl.se/ca/cacert-{ver_dashed}.pem",
                        None),
}

COLUMNS = ["pkgname", "kind", "source", "repo", "ref", "tar", "tar_url", "tar_url_fallback",
           "sha256", "arch_pkg", "version", "desc"]


def fetch(name):
    url = ARCH_API.format(name)
    for attempt in range(1, HTTP_ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(url, timeout=HTTP_TIMEOUT) as resp:
                data = json.load(resp)
            break
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as exc:
            if attempt == HTTP_ATTEMPTS:
                print(f"[!] 查询Arch失败 {name}(重试{HTTP_ATTEMPTS}次): {exc}", file=sys.stderr)
                return None
            print(f"[!] 查询Arch失败 {name}: {exc}; {HTTP_BACKOFF}s后重试 "
                  f"({attempt}/{HTTP_ATTEMPTS - 1})", file=sys.stderr)
            time.sleep(HTTP_BACKOFF)
    for item in data.get("results", []):
        if item["pkgname"] == name:
            return item
    return None


def base_version(component, version):
    base = component.get("version_of") or component["pkg"]
    return version.split(".r")[0] if base == "pacman" else version


def derive_ref(component, version):
    if not version or component["arch"] is None:
        return "", "", "", ""

    base = component.get("version_of") or component["pkg"]
    parts = version.split(".")
    fields = dict(ver=version, maj=parts[0],
                  ver_dashed="-".join(parts),
                  ver_curl="_".join(parts) if base == "curl" else "")

    if base in TARBALLS:
        tar_tpl, url_tpl, fallback_tpl = TARBALLS[base]
        return ("", tar_tpl.format(**fields), url_tpl.format(**fields),
                fallback_tpl.format(**fields) if fallback_tpl else "")

    if component["ref"]:
        return component["ref"].format(**fields), "", "", ""

    if component["url"]:
        return "", "", component["url"].format(**fields), ""

    return "", "", "", ""


def build_rows():
    cache = {}
    rows, problems = [], []

    for component in COMPONENTS:
        pkg = component["pkg"]
        arch_pkg = component["arch"]
        source = component.get("source") or "arch"
        version_src = component.get("version_of") or arch_pkg

        if source == "arch":
            version = ""
            if not version_src:
                problems.append(f"{pkg}: source=arch但没有可同步的Arch包名")
            else:
                if version_src not in cache:
                    cache[version_src] = fetch(version_src)
                item = cache[version_src]
                if item is None:
                    problems.append(f"{pkg}: 取不到Arch包{version_src}")
                else:
                    version = base_version(component, item["pkgver"])
        else:
            version = component.get("version") or ""
            if not version:
                problems.append(f"{pkg}: source={source}但没有给version")

        desc = component["desc"]
        if desc is None and arch_pkg:
            if arch_pkg not in cache:
                cache[arch_pkg] = fetch(arch_pkg)
            item = cache[arch_pkg]
            desc = (item or {}).get("pkgdesc") or ""

        if not desc:
            problems.append(f"{pkg}: 没有描述(Arch无{arch_pkg}且未提供本地描述)")
        ref, tar, tar_url, tar_fallback = derive_ref(component, version) if version else ("", "", "", "")

        pinned = component.get("sha256")
        if isinstance(pinned, dict):
            digest = pinned.get(version, "")
            known = ", ".join(sorted(pinned)) or "无"
        else:
            digest = pinned or ""
            known = "已钉" if digest else "无"
        if tar and not digest:
            problems.append(f"{pkg}: {tar}没有对应版本{version or '?'}的sha256"
                            f"(已钉的版本:{known});下载它就无法校验,拒绝生成清单")

        repo = REPOS.get(component.get("version_of") or pkg, REPOS.get(pkg, "")) if ref else ""
        rows.append([
            pkg, component["kind"], source, repo, ref, tar, tar_url, tar_fallback,
            digest, arch_pkg or "", version, desc or "",
        ])

    return rows, problems


def summarize(rows):
    shipped = sum(1 for row in rows if row[1] != "toolchain")
    return f"{shipped}个软件包+{len(rows) - shipped}项构建输入"


def render(rows):
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(COLUMNS)
    writer.writerows(rows)
    return buffer.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="只校验,不写文件")
    parser.add_argument("--print", dest="show", action="store_true", help="打到标准输出")
    args = parser.parse_args()

    rows, problems = build_rows()
    if problems:
        for problem in problems:
            print(f"[-] {problem}", file=sys.stderr)
        return 1

    text = render(rows)

    if args.show:
        sys.stdout.write(text)
        return 0

    if args.check:
        current = MANIFEST.read_text(encoding="utf-8") if MANIFEST.exists() else ""
        if current != text:
            print(f"[-] {MANIFEST.relative_to(REPO_ROOT)}与Arch上游不一致,请运行./scripts/sync-archlinux.py", file=sys.stderr)
            return 1
        print(f"[+] 组件清单与上游一致({summarize(rows)})")
        return 0

    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(text, encoding="utf-8")
    print(f"[+] 已写入{MANIFEST.relative_to(REPO_ROOT)}({summarize(rows)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
