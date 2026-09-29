#!/usr/bin/env python3
import json
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

LIST_FIELDS = {"DEPENDS"}

FIELD_MAP = {
    "name": "NAME",
    "version": "VERSION",
    "description": "DESC",
    "filename": "FILENAME",
    "size": "CSIZE",
    "installedSize": "ISIZE",
    "sha256": "SHA256SUM",
    "url": "URL",
    "license": "LICENSE",
    "arch": "ARCH",
    "buildDate": "BUILDDATE",
    "packager": "PACKAGER",
    "depends": "DEPENDS",
}


def parse_desc(text: str) -> dict:
    fields: dict[str, list[str]] = {}
    key = None
    for line in text.split("\n"):
        if not line:
            continue
        if line.startswith("%") and line.endswith("%") and len(line) > 2:
            key = line[1:-1]
            fields.setdefault(key, [])
        elif key is not None:
            fields[key].append(line)
    return fields


def coerce(raw: str) -> object:
    return int(raw) if raw.lstrip("-").isdigit() and len(raw) < 19 else raw


def main() -> int:
    if len(sys.argv) != 3:
        print(f"用法:{sys.argv[0]} <db.tar.zst> <输出路径>", file=sys.stderr)
        return 2

    db_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])

    if not db_path.is_file():
        print(f"[-] 错误:软件源数据库不存在:{db_path}", file=sys.stderr)
        return 1

    packages = []
    with tempfile.TemporaryDirectory() as tmp:
        raw_tar = Path(tmp) / "db.tar"
        subprocess.run(
            f"zstd -dc {db_path} > {raw_tar}",
            shell=True,
            check=True,
        )
        with tarfile.open(raw_tar) as tf:
            for member in tf.getmembers():
                if not member.isfile() or member.name.count("/") != 1:
                    continue
                if Path(member.name).name != "desc":
                    continue
                extracted = tf.extractfile(member)
                if extracted is None:
                    continue
                fields = parse_desc(extracted.read().decode("utf-8"))

                entry = {}
                for json_key, desc_key in FIELD_MAP.items():
                    values = fields.get(desc_key, [])
                    if not values:
                        entry[json_key] = None
                    elif desc_key in LIST_FIELDS:
                        entry[json_key] = values
                    else:
                        if len(values) > 1:
                            print(
                                f"[-] 警告:{fields.get('NAME', ['?'])[0]}的"
                                f"%{desc_key}%有{len(values)}行,取首行",
                                file=sys.stderr,
                            )
                        entry[json_key] = coerce(values[0])
                packages.append(entry)

    if not packages:
        print("[-] 错误:数据库中没有解析出任何软件包", file=sys.stderr)
        return 1

    required = ("name", "version", "filename", "size", "sha256")
    broken = [
        p["name"]
        for p in packages
        if any(p[k] is None for k in required)
    ]
    if broken:
        print(
            f"[-] 错误:以下包缺少下载必需字段,已拒绝写入索引:{', '.join(broken)}",
            file=sys.stderr,
        )
        return 1

    packages.sort(key=lambda p: p["name"])

    out_path.write_text(
        json.dumps(
            {
                "schema": 1,
                "db": db_path.name,
                "count": len(packages),
                "packages": packages,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"[+] UI索引已生成:{out_path}({len(packages)}个软件包)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
