#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
smoke_root=$(mktemp -d)
cleanup() {
  rm -rf "$smoke_root"
}
trap cleanup EXIT HUP INT TERM

version=v0.0.0-test
export SOURCE_DATE_EPOCH=1700000000
"$project_root/scripts/package-release.sh" "$version" "$smoke_root/first" >/dev/null
"$project_root/scripts/package-release.sh" "$version" "$smoke_root/second" >/dev/null

expected_assets=(
  SHA256SUMS
  "pyft-wheel-gil-preflight_${version}_darwin_amd64.tar.gz"
  "pyft-wheel-gil-preflight_${version}_darwin_arm64.tar.gz"
  "pyft-wheel-gil-preflight_${version}_linux_amd64.tar.gz"
  "pyft-wheel-gil-preflight_${version}_linux_arm64.tar.gz"
)
mapfile -t actual_assets < <(find "$smoke_root/first" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
[[ ${actual_assets[*]} == "${expected_assets[*]}" ]]

(
  cd "$smoke_root/first"
  sha256sum --check --strict SHA256SUMS >/dev/null
)
cmp "$smoke_root/first/SHA256SUMS" "$smoke_root/second/SHA256SUMS"
for archive in "$smoke_root/first"/*.tar.gz; do
  cmp "$archive" "$smoke_root/second/${archive##*/}"
  mapfile -t members < <(tar -tzf "$archive")
  [[ ${#members[@]} -eq 5 ]]
  [[ ${members[1]} == */LICENSE ]]
  [[ ${members[2]} == */README.md ]]
  [[ ${members[3]} == */SECURITY.md ]]
  [[ ${members[4]} == */pyft-wheel-gil-preflight ]]

  archive_name=${archive##*/}
  target=${archive_name#pyft-wheel-gil-preflight_"${version}"_}
  target=${target%.tar.gz}
  target_os=${target%_*}
  target_arch=${target#*_}
  provenance_root="$smoke_root/provenance/$target"
  mkdir -p "$provenance_root"
  tar -xzf "$archive" -C "$provenance_root"
  binary="$provenance_root/pyft-wheel-gil-preflight_${version}_${target_os}_${target_arch}/pyft-wheel-gil-preflight"
  cmp "$project_root/LICENSE" "${binary%/*}/LICENSE"
  cmp "$project_root/README.md" "${binary%/*}/README.md"
  cmp "$project_root/SECURITY.md" "${binary%/*}/SECURITY.md"
  metadata=$(go version -m "$binary")
  printf '%s\n' "$metadata" | grep -Fq $'\tpath\tgithub.com/kentomk/pyft-wheel-gil-preflight/cmd/pyft-wheel-gil-preflight'
  printf '%s\n' "$metadata" | grep -Fq $'\tmod\tgithub.com/kentomk/pyft-wheel-gil-preflight\t(devel)'
  if printf '%s\n' "$metadata" | grep -q $'^\tdep\t'; then
    echo 'release binary contains an unexpected Go dependency module' >&2
    exit 1
  fi
  printf '%s\n' "$metadata" | grep -Fq "GOOS=$target_os"
  printf '%s\n' "$metadata" | grep -Fq "GOARCH=$target_arch"
  printf '%s\n' "$metadata" | grep -Fq 'CGO_ENABLED=0'
done

host_os=$(go env GOOS)
host_arch=$(go env GOARCH)
host_archive="$smoke_root/first/pyft-wheel-gil-preflight_${version}_${host_os}_${host_arch}.tar.gz"
[[ -f $host_archive ]]
mkdir "$smoke_root/extracted"
tar -xzf "$host_archive" -C "$smoke_root/extracted"
host_binary="$smoke_root/extracted/pyft-wheel-gil-preflight_${version}_${host_os}_${host_arch}/pyft-wheel-gil-preflight"
[[ $("$host_binary" version) == "pyft-wheel-gil-preflight $version" ]]

mkdir "$smoke_root/nonempty"
printf 'sentinel\n' >"$smoke_root/nonempty/keep"
if "$project_root/scripts/package-release.sh" "$version" "$smoke_root/nonempty" >/dev/null 2>&1; then
  echo 'packager accepted a non-empty output directory' >&2
  exit 1
fi
[[ $(cat "$smoke_root/nonempty/keep") == sentinel ]]
