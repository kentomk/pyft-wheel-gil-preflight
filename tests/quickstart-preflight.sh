#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
quickstart="$project_root/scripts/quickstart.sh"

non_executable=$(mktemp)
trap 'rm -f "$non_executable"' EXIT
if "$quickstart" "$non_executable" >"$non_executable.out" 2>&1; then
  printf '%s\n' 'quickstart accepted a non-executable target' >&2
  exit 1
fi
grep -Fxq "quickstart: Python executable is not executable: $non_executable" "$non_executable.out"
rm -f "$non_executable.out"

if "$quickstart" /usr/bin/python3 >"$non_executable.out" 2>&1; then
  printf '%s\n' 'quickstart accepted a non-free-threaded target' >&2
  exit 1
fi
grep -Fxq 'quickstart: target must be CPython 3.14t with the GIL disabled before import' "$non_executable.out"
