# Security policy

## Supported versions

Security fixes are developed on the current `main` branch. No released version exists yet.

## Untrusted wheel boundary

Importing a Python wheel executes arbitrary code. `pyft-wheel-gil-preflight` does not sandbox that code. Run it only on a wheel you trust and built yourself, inside an ephemeral environment without secrets or network authority. The tool deliberately does not report child stdout, stderr, warning text, environment values, or wheel contents.

Archive extraction rejects traversal, absolute paths, duplicate paths, symlink entries, excessive entry counts, and excessive expanded size. Import execution is time-bounded. Linux and macOS probes use a dedicated process group that is terminated after the direct child exits or on failure. Stdout and stderr are each bounded to 16 KiB while the process runs; their content is never copied into a report. This remains defense in depth, not a sandbox.

The composite Action passes `wheel`, `python`, and newline-delimited module inputs as literal arguments without shell evaluation. Its default source-build route sets `GOPROXY=off`; it neither resolves dependencies nor downloads an executable. Pin the Action to a reviewed full commit SHA and keep credentials out of the wheel-inspection job.

Release gates scan tracked text without printing matched content, require the MIT license and zero external Go modules, and inspect each archive's Go build metadata for the expected module, target, and `CGO_ENABLED=0`. These are bounded policy checks, not proof that source or binaries contain no vulnerability or secret.

The pinned alternatives comparison creates a temporary Python environment and installs third-party test tools from the configured package index. It is an explicit publisher-review test, not part of the offline Action, runtime, or release archive. Run it only in an ephemeral credential-free job; its wheel and package contents are not treated as trusted input to the checker.

The optional public-wheel comparison downloads and imports checksum-pinned third-party code. It is restricted to the publisher-review environment, validates PyPI metadata, HTTPS status, file size, and SHA-256 before import, and runs without credentials. PyPI metadata for the fixture does not state a license, so the wheel must never be committed, vendored, copied into an Action, or included in a release.

## Reporting a vulnerability

Do not publish secrets or exploit details in a public issue. If no private reporting route is available, open a minimal public issue that asks the maintainer to establish a private channel, without including sensitive details. Matsuki Kento (`@kentomk`) is an automated AI agent and will prioritize secret exposure, archive escape, and orphan-process reports over features.
