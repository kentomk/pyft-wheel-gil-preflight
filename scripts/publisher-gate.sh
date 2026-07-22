#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
publisher_tmp=$(mktemp -d)
cleanup() {
  chmod -R u+w "$publisher_tmp" 2>/dev/null || true
  rm -rf "$publisher_tmp"
}
trap cleanup EXIT HUP INT TERM

[[ $(uname -s) == Linux && $(uname -m) == aarch64 ]] || {
  printf '%s\n' 'publisher gate requires the Linux aarch64 broker host' >&2
  exit 1
}
[[ $(go env GOVERSION) == go1.26.5 ]] || {
  printf '%s\n' 'publisher gate requires Go 1.26.5' >&2
  exit 1
}
[[ $(zig version) == 0.16.0 ]] || {
  printf '%s\n' 'publisher gate requires Zig 0.16.0' >&2
  exit 1
}
command -v actionlint >/dev/null 2>&1 || {
  printf '%s\n' 'publisher gate requires actionlint' >&2
  exit 1
}

runtime_url='https://github.com/astral-sh/python-build-standalone/releases/download/20260718/cpython-3.14.6%2B20260718-aarch64-unknown-linux-gnu-freethreaded-install_only.tar.gz'
runtime_sha256='746e3eca9ef946bc5415492c2fd8bee4795108e79cb703dfebf34b146b2deb5a'
http_status=$(curl -sS -L --proto '=https' --tlsv1.2 -o "$publisher_tmp/python.tar.gz" -w '%{http_code}' "$runtime_url")
case "$http_status" in
  200) ;;
  401|403|429)
    printf 'runtime read blocked with HTTP %s\n' "$http_status" >&2
    exit 1
    ;;
  *)
    printf 'unexpected runtime HTTP status %s\n' "$http_status" >&2
    exit 1
    ;;
esac
actual_sha256=$(sha256sum "$publisher_tmp/python.tar.gz" | awk '{print $1}')
[[ $actual_sha256 == "$runtime_sha256" ]] || {
  printf '%s\n' 'runtime checksum mismatch' >&2
  exit 1
}
tar -xzf "$publisher_tmp/python.tar.gz" -C "$publisher_tmp"

PYFT_TEST_PYTHON="$publisher_tmp/python/bin/python3.14t" \
CC='zig cc' \
CGO_ENABLED=1 \
GOTOOLCHAIN=local \
  "$project_root/scripts/release-gate.sh"

CC='zig cc' "$project_root/tests/alternatives-comparison.sh" \
  "$publisher_tmp/python/bin/python3.14t"

"$project_root/tests/public-wheel-comparison.sh" \
  "$publisher_tmp/python/bin/python3.14t"
