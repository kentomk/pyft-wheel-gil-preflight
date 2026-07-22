#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf '%s\n' 'usage: tests/public-wheel-comparison.sh /path/to/python3.14t' >&2
  exit 2
fi

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
target_python=$1
comparison_tmp=$(mktemp -d)
cleanup() {
  chmod -R u+w "$comparison_tmp" 2>/dev/null || true
  rm -rf "$comparison_tmp"
}
trap cleanup EXIT HUP INT TERM

readarray -t runtime_identity < <("$target_python" -I -c 'import platform, sys, sysconfig; assert sys.version_info[:2] == (3, 14); assert sysconfig.get_config_var("Py_GIL_DISABLED") == 1; assert not sys._is_gil_enabled(); print(sys.platform); print(platform.machine())')
[[ ${runtime_identity[0]} == linux ]] || {
  printf '%s\n' 'public wheel comparison currently requires Linux' >&2
  exit 2
}

case "${runtime_identity[1]}" in
  aarch64|arm64)
    wheel_filename='safelz4-0.2.1-cp314-cp314t-manylinux_2_17_aarch64.manylinux2014_aarch64.whl'
    expected_sha256='9dbccecf1c9738e2122c3bf83bc7c16e9aa0d08e5ee3aaae335a9d33574e8c65'
    ;;
  x86_64|amd64)
    wheel_filename='safelz4-0.2.1-cp314-cp314t-manylinux_2_17_x86_64.manylinux2014_x86_64.whl'
    expected_sha256='566ddf149ecd7923396bb3f8a1420d47eb809e9d84a8f0669c651418bd4d16fb'
    ;;
  *)
    printf 'unsupported public wheel comparison architecture: %s\n' "${runtime_identity[1]}" >&2
    exit 2
    ;;
esac

metadata_url='https://pypi.org/pypi/safelz4/0.2.1/json'
metadata_status=$(curl -sS -L --proto '=https' --tlsv1.2 \
  -o "$comparison_tmp/metadata.json" -w '%{http_code}' "$metadata_url")
case "$metadata_status" in
  200) ;;
  401|403|429)
    printf 'public wheel metadata read blocked with HTTP %s\n' "$metadata_status" >&2
    exit 1
    ;;
  *)
    printf 'unexpected public wheel metadata HTTP status %s\n' "$metadata_status" >&2
    exit 1
    ;;
esac

readarray -t wheel_metadata < <(jq -er --arg filename "$wheel_filename" '
  [.urls[] | select(.filename == $filename and .packagetype == "bdist_wheel")]
  | if length == 1 then .[0] else error("expected exactly one wheel") end
  | .url, .digests.sha256, (.size | tostring)
' "$comparison_tmp/metadata.json")
[[ ${#wheel_metadata[@]} -eq 3 ]]
wheel_url=${wheel_metadata[0]}
metadata_sha256=${wheel_metadata[1]}
wheel_size=${wheel_metadata[2]}
[[ $wheel_url == https://files.pythonhosted.org/packages/*/"$wheel_filename" ]]
[[ $metadata_sha256 == "$expected_sha256" ]]
[[ $wheel_size =~ ^[0-9]+$ && $wheel_size -gt 0 && $wheel_size -le 1048576 ]]

wheel="$comparison_tmp/$wheel_filename"
wheel_status=$(curl -sS -L --proto '=https' --tlsv1.2 \
  -o "$wheel" -w '%{http_code}' "$wheel_url")
case "$wheel_status" in
  200) ;;
  401|403|429)
    printf 'public wheel read blocked with HTTP %s\n' "$wheel_status" >&2
    exit 1
    ;;
  *)
    printf 'unexpected public wheel HTTP status %s\n' "$wheel_status" >&2
    exit 1
    ;;
esac
[[ $(stat -c '%s' "$wheel") == "$wheel_size" ]]
actual_sha256=$(sha256sum "$wheel" | awk '{print $1}')
[[ $actual_sha256 == "$expected_sha256" ]]

"$target_python" -m venv "$comparison_tmp/venv"
"$comparison_tmp/venv/bin/python" -m pip install \
  --quiet --disable-pip-version-check --no-deps "$wheel"
"$comparison_tmp/venv/bin/python" -I -W ignore - <<'PY'
import sys

before = sys._is_gil_enabled()
import safelz4
after = sys._is_gil_enabled()
assert before is False and after is True
PY

go build -o "$comparison_tmp/pyft-wheel-gil-preflight" \
  "$project_root/cmd/pyft-wheel-gil-preflight"
set +e
checker_output=$("$comparison_tmp/pyft-wheel-gil-preflight" check \
  --wheel "$wheel" --python "$target_python" 2>&1)
checker_status=$?
set -e
[[ $checker_status -eq 1 ]]
[[ $checker_output == 'PGP001 safelz4._safelz4_rs: import re-enabled the GIL' ]]

printf '%s\n' 'checksum-pinned public wheel comparison passed'
