#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/python3.14t" >&2
  exit 2
fi

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failure_tmp=$(mktemp -d)
trap 'rm -rf "$failure_tmp"' EXIT
wheel_tag=$("$1" -I -c 'import sys, sysconfig; print(f"cp{sys.version_info.major}{sys.version_info.minor}-cp{sys.version_info.major}{sys.version_info.minor}t-{sysconfig.get_platform().replace(chr(45), chr(95)).replace(chr(46), chr(95))}")')
fixture_wheel="$failure_tmp/fixture-0.0.0-$wheel_tag.whl"

"$project_root/scripts/build-fixture-wheel.sh" "$1" "$fixture_wheel" >/dev/null
go build -o "$failure_tmp/tool" "$project_root/cmd/pyft-wheel-gil-preflight"

for module in import_error hang flood stderr_secret signal_term; do
  set +e
  output=$("$failure_tmp/tool" check \
    --wheel "$fixture_wheel" \
    --python "$1" \
    --module "fixture_fail.$module" \
    --timeout 200ms \
    --format json 2>&1)
  status=$?
  set -e
  if [[ $status -ne 2 ]]; then
    echo "expected exit 2 for $module, got $status" >&2
    exit 1
  fi
  if [[ $output == *PYFT_SECRET_CANARY* ]]; then
    echo "secret canary escaped for $module" >&2
    exit 1
  fi
done

"$failure_tmp/tool" check \
  --wheel "$fixture_wheel" \
  --python "$1" \
  --module fixture_fail.descendant_hold \
  --timeout 1s >/dev/null
