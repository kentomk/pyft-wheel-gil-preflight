#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/python3.14t" >&2
  exit 2
fi

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
quick_tmp=$(mktemp -d)
trap 'rm -rf "$quick_tmp"' EXIT
wheel_tag=$("$1" -I -c 'import sys, sysconfig; print(f"cp{sys.version_info.major}{sys.version_info.minor}-cp{sys.version_info.major}{sys.version_info.minor}t-{sysconfig.get_platform().replace(chr(45), chr(95)).replace(chr(46), chr(95))}")')
fixture_wheel="$quick_tmp/fixture-0.0.0-$wheel_tag.whl"

"$project_root/scripts/build-fixture-wheel.sh" "$1" "$fixture_wheel" >/dev/null
go build -o "$quick_tmp/pyft-wheel-gil-preflight" "$project_root/cmd/pyft-wheel-gil-preflight"
set +e
"$quick_tmp/pyft-wheel-gil-preflight" check --wheel "$fixture_wheel" --python "$1"
status=$?
set -e
if [[ $status -ne 1 ]]; then
  echo "expected PGP001 and exit 1, got $status" >&2
  exit 1
fi
