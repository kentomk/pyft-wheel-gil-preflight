# Changelog

## Unreleased

- Replace pre-release installation text and the Action SHA placeholder with the verified `v0.1.0` release and successful public-main revision.
- Add the reviewed v2 publisher contract, bounded repository payload preflight, and English installation path.
- Add an isolated exact-version alternatives comparison that reproduces the ordinary-test and binary-policy false green before requiring `PGP001`.
- Make original fixture wheels standards-complete with deterministic metadata and `RECORD` so maintained wheel tooling can inspect and install them.
- Add an optional checksum-pinned public `safelz4 0.2.1` wheel comparison with an explicit non-redistribution gate.
- Fail closed before import when the wheel filename's Python, free-threaded ABI, or platform tag is incompatible with the target CPython runtime.
- Add the target runtime contract to JSON output and lock text/JSON exit 0, 1, and 2 output with golden tests.
- Test exact archive entry-count and expanded-size limits.
- Add an offline source-built composite Action with literal argv handling and exit 0/1/2 propagation smoke tests.
- Add reproducible Linux/macOS amd64/arm64 archives, checksums, embedded versions, and a repairable release workflow.
- Add content-safe secret scanning, license/dependency allowlists, archive provenance checks, and a checksum-pinned publisher gate.
- Add the initial Go CLI with explicit-module wheel inspection.
- Add isolated free-threaded Python import and `PGP001` detection.
- Add original bad/good C extension fixtures, English documentation, CI, and quality checks.
- Discover top-level, nested, and leading-underscore native modules and inspect each in a fresh process.
- Bound child output and clean Linux/macOS process groups across timeout, signal, descendant, and import failures.
