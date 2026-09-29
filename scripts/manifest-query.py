#!/usr/bin/env python3
"""读取manifest/components.manifest(CSV)里某个包的某个字段。

用法:
    ./scripts/manifest-query.py <pkgname> <字段名>
    ./scripts/manifest-query.py --list

退出码:
    0:找到(值可能为空串)
    2:清单里没有这个包
    3:字段名不在表头里
"""

import csv
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "manifest" / "components.manifest"


def load():
    if not MANIFEST.exists():
        print(f"组件清单不存在:{MANIFEST}\n请先运行./scripts/sync-archlinux.py", file=sys.stderr)
        raise SystemExit(2)
    with MANIFEST.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def main(argv):
    if len(argv) == 2 and argv[1] == "--list":
        for name in load()[0].keys():
            print(name)
        return 0

    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 3

    pkgname, field = argv[1], argv[2]
    rows = load()
    if not rows:
        print(f"组件清单是空的:{MANIFEST}", file=sys.stderr)
        return 2
    if field not in rows[0]:
        print(f"清单里没有字段{field}(可用字段:{', '.join(rows[0].keys())})", file=sys.stderr)
        return 3

    for row in rows:
        if row.get("pkgname") == pkgname:
            print(row.get(field) or "")
            return 0

    print(f"组件清单里没有{pkgname},请检查scripts/sync-archlinux.py", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
