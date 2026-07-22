#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_root"

test -z "$(gofmt -l .)"
go test ./...
go vet ./...
go build ./cmd/pyft-wheel-gil-preflight
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh tests/*.sh
fi
if command -v actionlint >/dev/null 2>&1; then
  actionlint
fi
tests/package-release-smoke.sh
tests/static-policy-smoke.sh

if [[ -n ${PYFT_TEST_PYTHON:-} ]]; then
  scripts/quickstart.sh "$PYFT_TEST_PYTHON"
  fixture_tmp=$(mktemp -d)
  trap 'rm -rf "$fixture_tmp"' EXIT
  wheel_tag=$("$PYFT_TEST_PYTHON" -I -c 'import sys, sysconfig; print(f"cp{sys.version_info.major}{sys.version_info.minor}-cp{sys.version_info.major}{sys.version_info.minor}t-{sysconfig.get_platform().replace(chr(45), chr(95)).replace(chr(46), chr(95))}")')
  fixture_wheel="$fixture_tmp/fixture-0.0.0-$wheel_tag.whl"
  scripts/build-fixture-wheel.sh "$PYFT_TEST_PYTHON" "$fixture_wheel" >/dev/null
  go build -o "$fixture_tmp/tool" ./cmd/pyft-wheel-gil-preflight
  "$fixture_tmp/tool" check --wheel "$fixture_wheel" --python "$PYFT_TEST_PYTHON" --module fixture_pkg.goodext
  scripts/failure-smoke.sh "$PYFT_TEST_PYTHON"
  tests/action-smoke.sh "$PYFT_TEST_PYTHON"
fi
