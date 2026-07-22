#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
patterns=(
  'A[K]IA[0-9A-Z]{16}'
  'gh[pousr]_[A-Za-z0-9]{36,255}'
  'github_p[a]t_[A-Za-z0-9_]{20,255}'
  'xox[baprs]-[A-Za-z0-9-]{10,255}'
  'AIza[0-9A-Za-z_-]{35}'
  '-----BEGIN ([A-Z ]+ )?PRIVATE K[E]Y-----'
)
pattern=$(IFS='|'; printf '%s' "${patterns[*]}")

files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  cd "$project_root"
  mapfile -d '' files < <(git ls-files -z --cached --others --exclude-standard)
fi

for file in "${files[@]}"; do
  [[ -f $file ]] || continue
  if LC_ALL=C grep -I -E -q -- "$pattern" "$file"; then
    printf '%s\n' 'secret-like content detected in tracked source' >&2
    exit 1
  fi
done
