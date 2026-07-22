#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf '%s\n' 'usage: tests/alternatives-comparison.sh /path/to/python3.14t' >&2
  exit 2
fi

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
target_python=$1
comparison_tmp=$(mktemp -d)
cleanup() {
  chmod -R u+w "$comparison_tmp" 2>/dev/null || true
  rm -rf "$comparison_tmp"
}
trap cleanup EXIT HUP INT TERM

"$target_python" -I -c 'import sys, sysconfig; assert sys.version_info[:2] == (3, 14); assert sysconfig.get_config_var("Py_GIL_DISABLED") == 1; assert not sys._is_gil_enabled()'
"$target_python" -m venv "$comparison_tmp/venv"
comparison_python="$comparison_tmp/venv/bin/python"
"$comparison_python" -m pip install \
  --quiet \
  --disable-pip-version-check \
  --only-binary=:all: \
  --requirement "$project_root/tests/alternatives-requirements.txt"
"$comparison_python" -m pip check

"$comparison_python" - <<'PY'
import importlib.metadata

expected = {
    "packaging": "26.2",
    "cibuildwheel": "4.1.0",
    "pytest-freethreaded": "0.1.0",
    "auditwheel": "6.7.0",
    "abi3audit": "0.0.26",
}
actual = {name: importlib.metadata.version(name) for name in expected}
if actual != expected:
    raise SystemExit(f"comparison version mismatch: {actual!r}")
PY

readarray -t runtime_identity < <("$target_python" -I -c 'import platform, sys, sysconfig; print(f"cp{sys.version_info.major}{sys.version_info.minor}"); print(sysconfig.get_platform().replace("-", "_").replace(".", "_")); print(platform.machine())')
python_tag=${runtime_identity[0]}
platform_tag=${runtime_identity[1]}
machine=${runtime_identity[2]}
wheel="$comparison_tmp/fixture-0.0.0-${python_tag}-${python_tag}t-${platform_tag}.whl"
CC=${CC:-cc} "$project_root/scripts/build-fixture-wheel.sh" "$target_python" "$wheel" >/dev/null

"$comparison_python" - "$wheel" "$python_tag" "$platform_tag" <<'PY'
import pathlib
import sys
from packaging.tags import Tag
from packaging.utils import parse_wheel_filename

wheel = pathlib.Path(sys.argv[1])
python_tag = sys.argv[2]
platform_tag = sys.argv[3]
name, version, build, tags = parse_wheel_filename(wheel.name)
expected = Tag(python_tag, f"{python_tag}t", platform_tag)
assert (str(name), str(version), build) == ("fixture", "0.0.0", ())
assert expected in tags
PY

case "$machine" in
  x86_64) cibw_arch=x86_64 ;;
  aarch64|arm64) cibw_arch=aarch64 ;;
  *) printf 'unsupported comparison architecture: %s\n' "$machine" >&2; exit 2 ;;
esac
mkdir -p "$comparison_tmp/package"
printf '%s\n' '[build-system]' 'requires = []' 'build-backend = "fixture_backend"' > "$comparison_tmp/package/pyproject.toml"
identifier=$("$comparison_tmp/venv/bin/cibuildwheel" --only "${python_tag}t-manylinux_${cibw_arch}" --print-build-identifiers "$comparison_tmp/package")
[[ $identifier == "${python_tag}t-manylinux_${cibw_arch}" ]]

"$comparison_tmp/venv/bin/auditwheel" show "$wheel" >/dev/null
# A cp314t extension is outside abi3audit's target ABI. Its non-strict default
# exits zero after skipping those binaries, so it cannot enforce this postcondition.
"$comparison_tmp/venv/bin/abi3audit" "$wheel" >/dev/null 2>&1

"$comparison_python" -m pip install --disable-pip-version-check --no-deps --force-reinstall "$wheel" >/dev/null
cat > "$comparison_tmp/test_badext.py" <<'PY'
def test_ordinary_import_succeeds():
    import badext
    assert badext.__name__ == "badext"
PY
"$comparison_tmp/venv/bin/pytest" -q --require-gil-disabled --threads 1 --iterations 1 "$comparison_tmp/test_badext.py" >/dev/null

go build -o "$comparison_tmp/pyft-wheel-gil-preflight" "$project_root/cmd/pyft-wheel-gil-preflight"
set +e
checker_output=$("$comparison_tmp/pyft-wheel-gil-preflight" check --wheel "$wheel" --python "$target_python" --module badext 2>&1)
checker_status=$?
set -e
[[ $checker_status -eq 1 ]]
[[ $checker_output == 'PGP001 badext: import re-enabled the GIL' ]]

printf '%s\n' 'pinned alternatives false-green comparison passed'
