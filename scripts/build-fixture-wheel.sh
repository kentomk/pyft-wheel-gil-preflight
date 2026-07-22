#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/python3.14t OUTPUT.whl" >&2
  exit 2
fi

python_bin=$1
output_wheel=$2
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_tmp=$(mktemp -d)
trap 'rm -rf "$fixture_tmp"' EXIT

readarray -t python_config < <("$python_bin" -I -c 'import sysconfig; print(sysconfig.get_path("include")); print(sysconfig.get_config_var("EXT_SUFFIX")); print(int(sysconfig.get_config_var("Py_GIL_DISABLED") or 0))')
include_dir=${python_config[0]}
extension_suffix=${python_config[1]}
gil_disabled=${python_config[2]}
if [[ $gil_disabled != 1 || -z $extension_suffix ]]; then
  echo "target is not a supported free-threaded CPython" >&2
  exit 2
fi

read -r -a compiler_command <<< "${CC:-cc}"
"${compiler_command[@]}" -shared -fPIC -I"$include_dir" "$project_root/testdata/extensions/badext.c" -o "$fixture_tmp/badext$extension_suffix"
"${compiler_command[@]}" -shared -fPIC -I"$include_dir" "$project_root/testdata/extensions/_goodext.c" -o "$fixture_tmp/_goodext$extension_suffix"
mkdir -p "$fixture_tmp/fixture_pkg" "$fixture_tmp/fixture.libs"
"${compiler_command[@]}" -shared -fPIC -I"$include_dir" "$project_root/testdata/extensions/goodext.c" -o "$fixture_tmp/fixture_pkg/goodext$extension_suffix"
printf '%s\n' '"Original fixture package."' > "$fixture_tmp/fixture_pkg/__init__.py"
printf '%s\n' 'pure Python files are ignored' > "$fixture_tmp/pure.py"
printf '%s\n' 'vendored shared libraries are ignored' > "$fixture_tmp/fixture.libs/libhelper.so"
mkdir -p "$fixture_tmp/fixture-0.0.0.dist-info"
cp "$project_root/LICENSE" "$fixture_tmp/fixture-0.0.0.dist-info/LICENSE"
cp -R "$project_root/testdata/failures" "$fixture_tmp/fixture_fail"

"$python_bin" -I - "$fixture_tmp" "$output_wheel" <<'PY'
import pathlib
import sys
import zipfile

import base64
import csv
import hashlib

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2]).resolve()
output.parent.mkdir(parents=True, exist_ok=True)
wheel_tag = output.name[:-4].rsplit("-", 3)[-3:]
if len(wheel_tag) != 3 or not all(wheel_tag):
    raise SystemExit("output must have a canonical wheel filename")

dist_info = root / "fixture-0.0.0.dist-info"
(dist_info / "METADATA").write_text(
    "Metadata-Version: 2.4\n"
    "Name: fixture\n"
    "Version: 0.0.0\n"
    "Summary: Original pyft-wheel-gil-preflight test fixture\n"
)
(dist_info / "WHEEL").write_text(
    "Wheel-Version: 1.0\n"
    "Generator: pyft-wheel-gil-preflight fixture builder\n"
    "Root-Is-Purelib: false\n"
    f"Tag: {'-'.join(wheel_tag)}\n"
)

record_path = dist_info / "RECORD"
record_rows = []
for path in sorted(root.rglob("*")):
    if path.is_file() and path != record_path:
        payload = path.read_bytes()
        digest = base64.urlsafe_b64encode(hashlib.sha256(payload).digest()).rstrip(b"=").decode()
        record_rows.append((path.relative_to(root).as_posix(), f"sha256={digest}", str(len(payload))))
record_rows.append((record_path.relative_to(root).as_posix(), "", ""))
with record_path.open("w", newline="") as record_file:
    csv.writer(record_file, lineterminator="\n").writerows(record_rows)

with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as wheel:
    for path in sorted(root.rglob("*")):
        if path.is_file():
            wheel.write(path, path.relative_to(root).as_posix())
PY
printf '%s\n' "$output_wheel"
