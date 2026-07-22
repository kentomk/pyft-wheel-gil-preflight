#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf '%s\n' 'usage: scripts/package-release.sh VERSION OUTPUT_DIRECTORY' >&2
  exit 2
fi

version=$1
output_directory=$2
if [[ ! $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'invalid semantic version: %s\n' "$version" >&2
  exit 2
fi

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "$output_directory"
output_directory=$(cd "$output_directory" && pwd -P)
if find "$output_directory" -mindepth 1 -print -quit | grep -q .; then
  printf 'output directory must be empty: %s\n' "$output_directory" >&2
  exit 2
fi

source_date_epoch=${SOURCE_DATE_EPOCH:-0}
if [[ ! $source_date_epoch =~ ^[0-9]+$ ]]; then
  printf '%s\n' 'SOURCE_DATE_EPOCH must be a non-negative integer' >&2
  exit 2
fi

release_tmp=$(mktemp -d "${TMPDIR:-/tmp}/pyft-wheel-gil-preflight-release.XXXXXX")
# shellcheck disable=SC2317 # invoked by trap
cleanup() {
  rm -rf "$release_tmp"
}
trap cleanup EXIT HUP INT TERM

targets=(linux/amd64 linux/arm64 darwin/amd64 darwin/arm64)
archives=()
for target in "${targets[@]}"; do
  target_os=${target%/*}
  target_arch=${target#*/}
  archive_root="pyft-wheel-gil-preflight_${version}_${target_os}_${target_arch}"
  package_directory="$release_tmp/$archive_root"
  mkdir -p "$package_directory"

  (
    cd "$project_root"
    CGO_ENABLED=0 GOOS="$target_os" GOARCH="$target_arch" \
      GOTOOLCHAIN=local GOWORK=off GOPROXY=off GOSUMDB=off \
      go build -trimpath -buildvcs=false \
      -ldflags="-buildid= -s -w -X main.version=$version" \
      -o "$package_directory/pyft-wheel-gil-preflight" \
      ./cmd/pyft-wheel-gil-preflight
  )
  cp "$project_root/README.md" "$project_root/LICENSE" "$project_root/SECURITY.md" "$package_directory/"
  chmod 0755 "$package_directory/pyft-wheel-gil-preflight"
  chmod 0644 "$package_directory/README.md" "$package_directory/LICENSE" "$package_directory/SECURITY.md"

  archive="$output_directory/$archive_root.tar.gz"
  tar --sort=name --format=ustar --owner=0 --group=0 --numeric-owner \
    --mtime="@$source_date_epoch" -C "$release_tmp" -cf - "$archive_root" |
    gzip -n -9 >"$archive"
  archives+=("${archive##*/}")
  rm -rf "$package_directory"
done

(
  cd "$output_directory"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${archives[@]}" >SHA256SUMS
  else
    shasum -a 256 "${archives[@]}" >SHA256SUMS
  fi
)

printf 'packaged %s reproducible archives for %s\n' "${#archives[@]}" "$version"
