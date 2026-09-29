#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
mkdir -p "$BUILD_DIR"
BIN="$BUILD_DIR/verify-packages"

echo -e "\033[1;34m[*] 正在编译包校验器...\033[0m"
HAVE_LIBALPM=0
if cc -O2 -o "$BIN" "$SCRIPT_DIR/verify-packages.c" -lalpm 2>/dev/null; then
    HAVE_LIBALPM=1
else
    echo -e "\033[1;33m[-] 未能编译实加载校验器,跳过libalpm段(缺少libalpm开发包?Arch:pacman,Debian/Ubuntu:libalpm-dev)\033[0m"
fi

if [[ $# -gt 0 ]]; then
    PACKAGES=("$@")
else
    mapfile -t PACKAGES < <(find "$REPO_ROOT/output/repo" -maxdepth 1 -name '*.pkg.tar.zst' | sort)
fi

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo -e "\033[1;31m[FAIL] 未找到任何软件包文件,无可校验对象(构建确实产出包了吗?)\033[0m"
    exit 1
fi

if [[ $HAVE_LIBALPM -eq 1 ]]; then
    echo -e "\033[1;34m[*] 正在校验${#PACKAGES[@]}个软件包(libalpm实加载)...\033[0m"
    fakeroot "$BIN" "${PACKAGES[@]}"
fi

REPO_DIR="$REPO_ROOT/output/repo"
if [[ -f "$REPO_DIR/index.json" ]]; then
    echo -e "\033[1;34m[*] 正在校验index.json与实际包文件的一致性...\033[0m"
    ( cd "$REPO_DIR" && python3 - "$REPO_DIR" <<'PY'
import hashlib, json, sys
from pathlib import Path

repo = Path(sys.argv[1])
index = json.loads((repo / "index.json").read_text(encoding="utf-8"))
failures = []

if index.get("count") != len(index.get("packages", [])):
    failures.append(f"count={index.get('count')}与实际条目数不符")

ovp = {p.name for p in repo.glob("*.pkg.tar.zst")}
listed = set()

for pkg in index["packages"]:
    name = pkg["name"]
    fname = pkg["filename"]
    listed.add(fname)
    path = repo / fname
    if not path.is_file():
        failures.append(f"{name}:索引指向的包文件不存在{fname}")
        continue
    actual_size = path.stat().st_size
    if actual_size != pkg["size"]:
        failures.append(f"{name}:size不符(索引{pkg['size']}/实际{actual_size})")
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    if h.hexdigest() != pkg["sha256"]:
        failures.append(f"{name}:sha256不符(会致客户端下载校验失败)")
    for dep in pkg.get("depends") or []:
        if dep not in {p["name"] for p in index["packages"]}:
            failures.append(f"{name}:悬空依赖{dep}")

for missing in sorted(ovp - listed):
    failures.append(f"包{missing}未出现在index.json中(前端将看不到它)")

if failures:
    for f in failures:
        print(f"\033[1;31m[FAIL] {f}\033[0m")
    sys.exit(1)

print(f"\033[1;32m[OK] index.json:{len(index['packages'])}个包,size/sha256/依赖全部一致\033[0m")
PY
    ) || exit 1

else
    echo -e "\033[1;31m[FAIL] 未找到$REPO_DIR/index.json,请先执行./scripts/update-repo.sh\033[0m"
    exit 1
fi

echo -e "\033[1;34m[*] 正在校验ELF链接闭包与逐包依赖覆盖...\033[0m"
audit_log="$(mktemp)"
trap 'rm -f "$audit_log"' EXIT
if "$SCRIPT_DIR/elfdeps.py" audit "$REPO_DIR" > "$audit_log"; then
    color="1;32"; tag="[OK]"
else
    color="1;31"; tag="[FAIL]"
fi

ESC=$'\e'
while IFS= read -r line; do
    if [[ -z "$line" ]]; then
        continue
    fi
    case "$line" in
        OK:*) line="${line#OK:}" ;;
    esac
    printf '%s[%sm%s %s%s[0m\n' "$ESC" "$color" "$tag" "$line" "$ESC"
done < "$audit_log"
[[ "$color" == "1;32" ]]
