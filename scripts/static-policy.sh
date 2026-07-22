#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$project_root"

[[ $(sed -n '1p' LICENSE) == 'MIT License' ]]
[[ $(GOTOOLCHAIN=local GOWORK=off GOPROXY=off GOSUMDB=off go list -mod=readonly -m all) == 'github.com/kento-matsuki/pyft-wheel-gil-preflight' ]]
[[ ! -e go.sum ]]
[[ -z $(git ls-files '*.whl') ]]

while IFS= read -r use_line; do
  [[ $use_line =~ @[0-9a-f]{40}([[:space:]]|$) ]] || {
    printf '%s\n' 'GitHub Actions dependencies must use a full commit SHA' >&2
    exit 1
  }
done < <(grep -R -h -E '^[[:space:]]*uses:' .github action.yml 2>/dev/null || true)

scripts/scan-secrets.sh
