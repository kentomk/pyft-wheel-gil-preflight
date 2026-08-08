#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/python3.14t" >&2
  exit 2
fi

target_python=$1
if [[ ! -x $target_python ]]; then
  echo "quickstart: Python executable is not executable: $target_python" >&2
  exit 2
fi

if ! "$target_python" -I -c '
import sys
import sysconfig

if sys.version_info[:2] != (3, 14):
    raise SystemExit("requires CPython 3.14")
if sysconfig.get_config_var("Py_GIL_DISABLED") != 1:
    raise SystemExit("requires a free-threaded CPython build")
if sys._is_gil_enabled():
    raise SystemExit("requires the GIL to be disabled before import")
' >/dev/null 2>&1; then
  echo "quickstart: target must be CPython 3.14t with the GIL disabled before import" >&2
  exit 2
fi

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
quick_tmp=$(mktemp -d)
trap 'rm -rf "$quick_tmp"' EXIT
wheel_tag=$("$target_python" -I -c 'import sys, sysconfig; print(f"cp{sys.version_info.major}{sys.version_info.minor}-cp{sys.version_info.major}{sys.version_info.minor}t-{sysconfig.get_platform().replace(chr(45), chr(95)).replace(chr(46), chr(95))}")')
fixture_wheel="$quick_tmp/fixture-0.0.0-$wheel_tag.whl"

"$project_root/scripts/build-fixture-wheel.sh" "$target_python" "$fixture_wheel" >/dev/null
go build -o "$quick_tmp/pyft-wheel-gil-preflight" "$project_root/cmd/pyft-wheel-gil-preflight"
set +e
"$quick_tmp/pyft-wheel-gil-preflight" check --wheel "$fixture_wheel" --python "$target_python"
status=$?
set -e
if [[ $status -ne 1 ]]; then
  echo "expected PGP001 and exit 1, got $status" >&2
  exit 1
fi
