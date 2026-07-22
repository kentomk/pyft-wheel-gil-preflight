#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/python3.14t" >&2
  exit 2
fi

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python_bin=$1
smoke_root=$(mktemp -d)
cleanup() {
  rm -rf "$smoke_root"
}
trap cleanup EXIT HUP INT TERM

wheel_tag=$("$python_bin" -I -c 'import sys, sysconfig; print(f"cp{sys.version_info.major}{sys.version_info.minor}-cp{sys.version_info.major}{sys.version_info.minor}t-{sysconfig.get_platform().replace(chr(45), chr(95)).replace(chr(46), chr(95))}")')
fixture_wheel="$smoke_root/fixture-0.0.0-$wheel_tag.whl"
"$project_root/scripts/build-fixture-wheel.sh" "$python_bin" "$fixture_wheel" >/dev/null
go build -trimpath -o "$smoke_root/tool" "$project_root/cmd/pyft-wheel-gil-preflight"

pass_output=$(env \
  GITHUB_ACTION_PATH="$project_root" \
  RUNNER_TEMP="$smoke_root/run" \
  PGP_ACTION_WHEEL="$fixture_wheel" \
  PGP_ACTION_PYTHON="$python_bin" \
  PGP_ACTION_MODULES=fixture_pkg.goodext \
  PGP_ACTION_FORMAT=json \
  "$project_root/scripts/action.sh")
printf '%s' "$pass_output" | grep -q '"violations":0'

set +e
violation_output=$(env \
  GITHUB_ACTION_PATH="$project_root" \
  RUNNER_TEMP="$smoke_root/run" \
  PGP_ACTION_BINARY="$smoke_root/tool" \
  PGP_ACTION_WHEEL="$fixture_wheel" \
  PGP_ACTION_PYTHON="$python_bin" \
  PGP_ACTION_MODULES=badext \
  PGP_ACTION_FORMAT=text \
  "$project_root/scripts/action.sh" 2>&1)
violation_status=$?
set -e
[[ $violation_status -eq 1 ]]
printf '%s' "$violation_output" | grep -q '^PGP001 badext:'

set +e
error_output=$(env \
  GITHUB_ACTION_PATH="$project_root" \
  RUNNER_TEMP="$smoke_root/run" \
  PGP_ACTION_BINARY="$smoke_root/tool" \
  PGP_ACTION_WHEEL="$fixture_wheel" \
  PGP_ACTION_PYTHON="$python_bin" \
  PGP_ACTION_MODULES='not-a-module' \
  PGP_ACTION_FORMAT=json \
  "$project_root/scripts/action.sh" 2>&1)
error_status=$?
set -e
[[ $error_status -eq 2 ]]
printf '%s' "$error_output" | grep -q '"errors":1'

if find "$smoke_root/run" -maxdepth 1 -name 'pyft-wheel-gil-preflight-action.*' -print -quit | grep -q .; then
  echo 'Action temporary directory was not cleaned' >&2
  exit 1
fi
