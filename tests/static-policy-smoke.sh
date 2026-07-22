#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
smoke_root=$(mktemp -d)
cleanup() {
  rm -rf "$smoke_root"
}
trap cleanup EXIT HUP INT TERM

printf '%s\n' 'ordinary fixture content' >"$smoke_root/safe"
"$project_root/scripts/scan-secrets.sh" "$smoke_root/safe"

canary='A''KIAIOSFODNN7EXAMPLE'
printf '%s\n' "$canary" >"$smoke_root/secret"
set +e
output=$("$project_root/scripts/scan-secrets.sh" "$smoke_root/secret" 2>&1)
status=$?
set -e
[[ $status -eq 1 ]]
[[ $output == 'secret-like content detected in tracked source' ]]
[[ $output != *"$canary"* ]]

"$project_root/scripts/static-policy.sh"
