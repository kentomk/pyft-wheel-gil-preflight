#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$project_root"

mapfile -d '' tracked_files < <(git ls-files -z)
file_count=${#tracked_files[@]}
((file_count >= 9 && file_count <= 200))
total_bytes=0
has_test=0
for path in "${tracked_files[@]}"; do
  [[ $path != /* && $path != *\\* && $path != ../* && $path != */../* ]]
  [[ -f $path && ! -L $path ]]
  size=$(stat -c %s -- "$path")
  ((size <= 512 * 1024))
  total_bytes=$((total_bytes + size))
  [[ $path == tests/* || $path == *_test.go ]] && has_test=1
done
((has_test == 1 && total_bytes <= 3 * 1024 * 1024))
if printf '%s\n' "${tracked_files[@]}" | grep -Eiq '(^|/)(\.env($|\.)|id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(pem|key|p12|pfx|whl)|credentials?\.json|secrets?\.)'; then
  printf '%s\n' 'publisher payload contains a credential-like or wheel path' >&2
  exit 1
fi
printf 'publisher payload preflight: %d files, %d bytes\n' "$file_count" "$total_bytes"
