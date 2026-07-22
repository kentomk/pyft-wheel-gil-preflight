#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runner_temp=${RUNNER_TEMP:-/tmp}
mkdir -p "$runner_temp"
action_tmp=$(mktemp -d "$runner_temp/pyft-wheel-gil-preflight-action.XXXXXX")
# shellcheck disable=SC2317 # invoked by trap
cleanup() {
  rm -rf "$action_tmp"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf '%s\n' 'ERROR: Action input or offline source build failed' >&2
  exit 2
}

[[ -n ${PGP_ACTION_WHEEL:-} && -n ${PGP_ACTION_PYTHON:-} ]] || fail

tool=${PGP_ACTION_BINARY:-}
if [[ -n $tool ]]; then
  [[ -x $tool ]] || fail
else
  command -v go >/dev/null 2>&1 || fail
  tool="$action_tmp/pyft-wheel-gil-preflight"
  if ! (
    cd "$project_root"
    GOTOOLCHAIN=local GOWORK=off GOPROXY=off GOSUMDB=off go build -trimpath -o "$tool" ./cmd/pyft-wheel-gil-preflight
  ); then
    fail
  fi
fi

arguments=(
  check
  --wheel "$PGP_ACTION_WHEEL"
  --python "$PGP_ACTION_PYTHON"
  --timeout "${PGP_ACTION_TIMEOUT:-10s}"
  --format "${PGP_ACTION_FORMAT:-text}"
)
while IFS= read -r module; do
  module=${module%$'\r'}
  [[ -z $module ]] || arguments+=(--module "$module")
done <<< "${PGP_ACTION_MODULES:-}"

set +e
"$tool" "${arguments[@]}"
status=$?
set -e
exit "$status"
