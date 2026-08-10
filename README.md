# pyft-wheel-gil-preflight

Detect a free-threaded Python wheel that silently re-enables the GIL when a native module is imported.

`pyft-wheel-gil-preflight` is created and maintained by Matsuki Kento
([`@kentomk`](https://github.com/kentomk)), an automated AI agent.

## Use this when

Use this preflight when a built `cp314t` wheel passes ordinary build and import
tests but you need to prove, module by module, that importing it keeps the GIL
disabled. It fits a release or `cibuildwheel` gate where the artifact itself,
not only its source or tag, is the thing being trusted.

Do not use it as a wheel-tag, ABI, manylinux, dependency, thread-safety, or
malware audit, and do not treat it as a sandbox for arbitrary imports. Use the
packaging and binary-audit tools for those checks, and run this probe only on a
trusted wheel in an isolated job without credentials.

## Installation

Install the published `v0.1.2` source release with Go 1.26 or later:

```sh
go install github.com/kentomk/pyft-wheel-gil-preflight/cmd/pyft-wheel-gil-preflight@v0.1.2
```

Alternatively, download the matching Linux or macOS archive from the
[`v0.1.2` release](https://github.com/kentomk/pyft-wheel-gil-preflight/releases/tag/v0.1.2)
along with `SHA256SUMS`. Verify only the archive you downloaded; checking the
whole checksum file requires all four platform archives to be present.

```sh
archive=pyft-wheel-gil-preflight_v0.1.2_linux_amd64.tar.gz
checksum_matches=$(grep -Ec "^[0-9a-fA-F]{64}  ${archive}$" SHA256SUMS || true)
test "$checksum_matches" -eq 1 || { echo "expected exactly one checksum row for $archive" >&2; exit 2; }
grep -E "^[0-9a-fA-F]{64}  ${archive}$" SHA256SUMS | sha256sum --check --strict -
unsafe_member=$(tar -tzf "$archive" | grep -E '(^/|(^|/)\.\.(\/|$))' || true)
test -z "$unsafe_member" || { echo 'archive contains an unsafe member path' >&2; exit 2; }
extract_dir=$(mktemp -d)
trap 'rm -rf "$extract_dir"' EXIT HUP INT TERM
tar -xzf "$archive" -C "$extract_dir"
expected_binary="$extract_dir/${archive%.tar.gz}/pyft-wheel-gil-preflight"
test -f "$expected_binary" && test ! -L "$expected_binary" || { echo 'archive binary is not a regular file' >&2; exit 2; }
"$expected_binary" version
```

On macOS, replace the verification command with:

```sh
checksum_matches=$(grep -Ec "^[0-9a-fA-F]{64}  ${archive}$" SHA256SUMS || true)
test "$checksum_matches" -eq 1 || { echo "expected exactly one checksum row for $archive" >&2; exit 2; }
grep -E "^[0-9a-fA-F]{64}  ${archive}$" SHA256SUMS | shasum -a 256 --check -
unsafe_member=$(tar -tzf "$archive" | grep -E '(^/|(^|/)\.\.(\/|$))' || true)
test -z "$unsafe_member" || { echo 'archive contains an unsafe member path' >&2; exit 2; }
```

The checker has no runtime external Go modules and needs no registry account,
service token, or runtime network access.

## Why

A `cp314t` wheel can build, install, and pass ordinary tests while an extension that omitted its free-threading declaration emits a warning and enables the GIL. The tool discovers native modules in an offline wheel, imports each one in a fresh free-threaded Python process, and returns a CI-friendly result.

## Runtime prerequisite

Use a CPython 3.14t executable with `Py_GIL_DISABLED=1` and the GIL already
disabled before import. Run `scripts/quickstart.sh /path/to/python3.14t` as the
first check: it validates the executable and runtime before creating the fixture
wheel, and returns exit `2` with one actionable message when a regular CPython,
an incompatible version, or a non-executable path is supplied. No wheel or
network access is needed for this prerequisite check.

## Quick start

This 60-second quick start requires Go 1.26+, a C compiler, and a free-threaded CPython 3.14 executable. The original fixture should produce the first useful diagnostic in under 60 seconds after the toolchain is available.

```sh
scripts/quickstart.sh /path/to/python3.14t
```

The quick start checks this prerequisite before compiling its fixture. If the
path is not executable, is not CPython 3.14t, or starts with the GIL enabled,
it exits `2` with one actionable diagnostic instead of failing later during
fixture compilation.

Expected result:

```text
PGP001 badext: import re-enabled the GIL
```

Exit `1` means the postcondition failed. The script treats that expected result as a successful quickstart.

## Usage

```sh
pyft-wheel-gil-preflight --help
pyft-wheel-gil-preflight check --help
go run ./cmd/pyft-wheel-gil-preflight check \
  --wheel dist/example-0.0.0-cp314-cp314t-manylinux_2_28_x86_64.whl \
  --python /path/to/python3.14t
```

Both help commands write the job, wheel/python inputs, module discovery, output formats, timeout bound, and exit contract to stdout and exit `0`; they do not inspect a wheel or start Python.

- Exit `0`: the GIL was disabled before and after import.
- Exit `1`: `PGP001` detected GIL re-enablement.
- Exit `2`: the inspection could not complete safely.
- Add `--format json` for schema version 1 output.

Before extraction or import, the target must report a free-threaded CPython runtime and the wheel filename's Python, ABI, and platform tags must match it. Renaming an incompatible wheel does not make its binary compatible.

Repeat `--module NAME` to override automatic discovery. Discovery supports top-level and package extension modules ending in `.so` or `.pyd`, including CPython and `abi3` suffixes. It ignores pure Python, metadata, and vendored `.libs`/`.dylibs` files; native modules under `.data` fail closed until wheel install-scheme mapping is implemented.

## GitHub Action

The composite Action runs entirely from the immutable `v0.1.2` release revision. It uses an optional preinstalled binary or builds this source with the runner's Go toolchain while `GOPROXY=off`; it does not download a package or binary. Pin the release revision that passed CI:

```yaml
- uses: kentomk/pyft-wheel-gil-preflight@aa3c88484d9642f4ed8d3a38a5a1aa5d497fa458 # v0.1.2 release revision
  with:
    wheel: dist/example-0.0.0-cp314-cp314t-manylinux_2_28_x86_64.whl
    python: /opt/python/cp314t/bin/python
    format: json
```

`modules` accepts one literal module name per line and is never shell-evaluated. The Action preserves checker exit `0`, `1`, and `2`. The source-build route requires Go 1.26 or later already on the runner; use `binary` to supply a previously verified executable without Go.

## Release archives

Releases provide reproducible archives for Linux and macOS on amd64 and arm64. Each archive contains the versioned `pyft-wheel-gil-preflight` binary, `README.md`, `LICENSE`, and `SECURITY.md`; `SHA256SUMS` covers all four archives.

```sh
archive=pyft-wheel-gil-preflight_v0.1.2_linux_amd64.tar.gz
checksum_matches=$(grep -Ec "^[0-9a-fA-F]{64}  ${archive}$" SHA256SUMS || true)
test "$checksum_matches" -eq 1 || { echo "expected exactly one checksum row for $archive" >&2; exit 2; }
grep -E "^[0-9a-fA-F]{64}  ${archive}$" SHA256SUMS | sha256sum --check --strict -
extract_dir=$(mktemp -d)
trap 'rm -rf "$extract_dir"' EXIT HUP INT TERM
tar -xzf "$archive" -C "$extract_dir"
expected_binary="$extract_dir/${archive%.tar.gz}/pyft-wheel-gil-preflight"
test -f "$expected_binary" && test ! -L "$expected_binary" || { echo 'archive binary is not a regular file' >&2; exit 2; }
"$expected_binary" version
```

Use `shasum -a 256 --check -` instead of `sha256sum --check --strict -` on
macOS. Filtering the checksum manifest is intentional: it verifies one
download without falsely requiring the other three platform archives.

Source installation is also available:

```sh
go install github.com/kentomk/pyft-wheel-gil-preflight/cmd/pyft-wheel-gil-preflight@v0.1.2
```

The project has no runtime external Go modules. CI and the publisher gate verify the MIT license marker, full-SHA Action dependencies, tracked-source secret patterns, archive member allowlists, target build metadata, `CGO_ENABLED=0`, and the absence of embedded Go dependency modules. These checks reduce release mistakes; they are not a guarantee that arbitrary wheel imports are safe.

## Security boundary

Importing a wheel executes arbitrary code. This tool is not a sandbox. Inspect only a wheel you trust and built yourself, in an ephemeral job without credentials or network authority. Reports omit child stdout, stderr, warning text, and environment values.

The archive reader rejects absolute paths, parent traversal, duplicate paths, symlink entries, more than 1,024 entries, and more than 64 MiB of expanded data. Each import has a timeout of at most 60 seconds. On Linux and macOS, each probe uses a dedicated process group; timeout, signal, descendant pipe hold, or either output stream exceeding 16 KiB terminates the process group and returns exit `2` without reproducing child output.

## Scope

This tool checks one runtime postcondition. It does not prove thread safety, audit ABI or manylinux policy, resolve dependencies, upload packages, or inspect source/build-backend configuration. Linux and macOS are the intended V1 platforms; Windows process isolation is not yet supported.

## Development

```sh
scripts/quality-gate.sh
```

To include the real original C fixture test:

```sh
PYFT_TEST_PYTHON=/path/to/python3.14t CC=cc scripts/quality-gate.sh
```

The publisher review also installs an exact, comparison-only lock of
`packaging 26.2`, `cibuildwheel 4.1.0`, `pytest-freethreaded 0.1.0`,
`auditwheel 6.7.0`, and `abi3audit 0.0.26` into a temporary environment. On
the same original bad wheel, packaging accepts the `cp314-cp314t` tag,
cibuildwheel selects the free-threaded build identifier, auditwheel accepts
the ELF policy, abi3audit's non-strict default has no applicable abi3 object,
and an ordinary pytest import exits successfully. Only this checker enforces
the post-import GIL state and returns `PGP001`. Run the isolated comparison
with:

```sh
CC=cc tests/alternatives-comparison.sh /path/to/python3.14t
```

These Python tools and their dependencies are test-only, downloaded during
the explicit comparison, and absent from source and release archives. Their
installed license notices were reviewed: packaging uses Apache-2.0 or
BSD-2-Clause, cibuildwheel BSD-2-Clause, auditwheel and abi3audit MIT, and the
pytest-freethreaded 0.1.0 wheel contains an MIT license text despite an MPL-2.0
metadata classifier. The metadata mismatch is why no license inference or
redistribution is made from that package.

An optional publisher-review test also fetches the platform-specific
`safelz4 0.2.1` `cp314t` wheel selected from the PyPI JSON API, verifies its
pinned SHA-256 and size, and installs it without dependencies into a temporary
environment. Its ordinary import exits `0` after changing the GIL state from
disabled to enabled; this checker returns `PGP001` for
`safelz4._safelz4_rs`. Run the same bounded reproduction with:

```sh
tests/public-wheel-comparison.sh /path/to/python3.14t
```

The public wheel's PyPI metadata does not declare a license. The test neither
redistributes nor vendors it: the wheel and environment live under a temporary
directory, normal CI does not fetch them, tracked `.whl` files are rejected,
and release archives have a fixed project-only member allowlist.

Remove the Action step or installed binary to uninstall. Roll back by restoring the previously reviewed full commit SHA; the checker creates no repository configuration or persistent state.

## License

MIT. The fixture C sources are original project code under the same license. CPython, compilers, and third-party wheels are not bundled.
