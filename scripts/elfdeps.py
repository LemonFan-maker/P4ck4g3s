#!/usr/bin/env python3
"""用法:
elfdeps.py needed <dir>
elfdeps.py provided <dir>
elfdeps.py index <repo_dir>
elfdeps.py resolve <repo_dir> <staging_dir> <pkgname>
elfdeps.py audit <repo_dir>
"""
from __future__ import annotations

import io
import os
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

NEEDED_LINE = re.compile(r"\(NEEDED\)[^\[]*\[([^\]]+)\]")
SONAME = re.compile(r"^lib.+\.so(\.\d+)*$")
READELF_ENV = {**os.environ, "LC_ALL": "C", "LANG": "C"}

SYSTEM_LIBS = frozenset({"libc.so", "libdl.so", "libm.so"})


def _elf_needed(blob: bytes) -> set[str]:
    if blob[:4] != b"\x7fELF":
        return set()
    with tempfile.NamedTemporaryFile(suffix=".elf") as tmp:
        tmp.write(blob)
        tmp.flush()
        res = subprocess.run(
            ["readelf", "-d", tmp.name], capture_output=True, text=True, env=READELF_ENV
        )
    return set(NEEDED_LINE.findall(res.stdout))


def provided_sonames(root: Path) -> set[str]:
    return {p.name for p in root.rglob("*") if SONAME.match(p.name)}


def needed_sonames(root: Path) -> set[str]:
    out: set[str] = set()
    for path in root.rglob("*"):
        if path.is_symlink() or not path.is_file():
            continue
        try:
            out.update(_elf_needed(path.read_bytes()))
        except OSError:
            continue
    return out


def _read_archive(pkg: Path) -> tarfile.TarFile | None:
    raw = subprocess.run(["zstd", "-dc", str(pkg)], capture_output=True).stdout
    if not raw:
        return None
    return tarfile.open(fileobj=io.BytesIO(raw))


def _meta(tf: tarfile.TarFile) -> tuple[str | None, set[str]]:
    name: str | None = None
    depends: set[str] = set()
    try:
        handle = tf.extractfile(".PKGINFO")
    except KeyError:
        return None, depends
    if handle is None:
        return None, depends
    for line in handle.read().decode("utf-8", "replace").splitlines():
        if name is None and line.startswith("pkgname = "):
            name = line.split("=", 1)[1].strip()
        elif line.startswith("depend = "):
            depends.add(line.split("=", 1)[1].strip())
    return name, depends


def scan_repo(
    repo: Path,
) -> tuple[dict[str, str], dict[str, set[str]], dict[str, set[str]], list[str]]:
    index: dict[str, str] = {}
    declared: dict[str, set[str]] = {}
    needed: dict[str, set[str]] = {}
    corrupt: list[str] = []
    for pkg in sorted(repo.glob("*.pkg.tar.zst")):
        try:
            tf = _read_archive(pkg)
            if tf is None:
                corrupt.append(f"{pkg.name}(zstd解压失败或为空)")
                continue
            with tf:
                name, deps = _meta(tf)
                if name is None:
                    corrupt.append(f"{pkg.name}(缺.PKGINFO或无pkgname)")
                    continue
                declared[name] = deps
                need: set[str] = set()
                for member in tf.getmembers():
                    base = Path(member.name).name
                    if member.issym() and SONAME.match(base):
                        index.setdefault(base, name)
                    elif member.isfile():
                        if SONAME.match(base):
                            index.setdefault(base, name)
                        try:
                            need.update(_elf_needed(tf.extractfile(member).read()))
                        except (OSError, KeyError):
                            continue
                needed[name] = need
        except (tarfile.TarError, OSError, EOFError) as exc:
            corrupt.append(f"{pkg.name}({type(exc).__name__}: {exc})")
    return index, declared, needed, corrupt


def package_index(repo: Path) -> dict[str, str]:
    index, _, _, _ = scan_repo(repo)
    return index


def resolve(repo: Path, staging: Path, pkgname: str) -> int:
    owned = provided_sonames(staging)
    index = package_index(repo)
    for soname in owned:
        index.setdefault(soname, pkgname)

    deps: set[str] = set()
    unresolved: list[str] = []
    for soname in sorted(needed_sonames(staging)):
        if soname in SYSTEM_LIBS:
            continue
        owner = index.get(soname)
        if owner is None:
            unresolved.append(soname)
        elif owner != pkgname:
            deps.add(owner)

    if unresolved:
        print(
            f"elfdeps:{pkgname}需要以下共享库,但没有任何包提供:"
            + ", ".join(unresolved),
            file=sys.stderr,
        )
        print(
            "链接器能链上去只说明构建时sysroot里有它,不代表装包时会带上它\n"
            "要么先构建并发布提供这些库的包(库包必须排在工具包之前),"
            "要么把该库并入本包",
            file=sys.stderr,
        )
        return 1

    for dep in sorted(deps):
        print(dep)
    return 0


def audit(repo: Path) -> int:
    index, declared, needed, corrupt = scan_repo(repo)
    failures: list[str] = [f"{pkg}无法读取:仓库里有损坏的包,请删除后重新构建" for pkg in corrupt]
    parsed = sum(len(s) for s in needed.values())
    if not needed or parsed == 0:
        print(f"未解析出任何DT_NEEDED(读包{len(needed)}个,解析0条):"
              "扫描逻辑失效(readelf可用?locale正确?),门禁未真正执行")
        return 1

    soname_total = 0
    for pkg in sorted(needed):
        implied: set[str] = set()
        for soname in sorted(needed[pkg]):
            if soname in SYSTEM_LIBS:
                continue
            soname_total += 1
            owner = index.get(soname)
            if owner is None:
                failures.append(
                    f"{soname}被{pkg}需要,但没有任何包提供该文件"
                )
            elif owner != pkg:
                implied.add(owner)
        missing = implied - declared.get(pkg, set())
        if missing:
            failures.append(
                f"{pkg}的DT_NEEDED指向{','.join(sorted(missing))},"
                f"但depends未声明:装本包时不会带上它们"
            )

    for line in failures:
        print(line)
    if failures:
        return 1

    print(
        f"OK:链接闭包{len(index)}个共享库文件,{soname_total}个DT_NEEDED全部有归属;"
        f"{len(needed)}个包的depends全部覆盖其DT_NEEDED"
    )
    return 0


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) >= 2 else ""
    if mode == "resolve" and len(argv) == 5:
        return resolve(Path(argv[2]), Path(argv[3]), argv[4])
    if mode == "audit" and len(argv) == 3:
        return audit(Path(argv[2]))
    if len(argv) == 3 and mode in {"needed", "provided", "index"}:
        target = Path(argv[2])
        if not target.exists():
            print(f"elfdeps:路径不存在:{target}", file=sys.stderr)
            return 2
        if mode == "index":
            for soname, owner in sorted(package_index(target).items()):
                print(f"{soname}\t{owner}")
            return 0
        result = needed_sonames(target) if mode == "needed" else provided_sonames(target)
        for name in sorted(result):
            print(name)
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except BrokenPipeError:
        os._exit(0)
