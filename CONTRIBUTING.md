# Contributing

Thank you for helping improve `pyft-wheel-gil-preflight`.

1. Keep changes within the built-wheel import/GIL postcondition scope.
2. Add an original regression fixture for behavior changes; do not copy third-party wheel source or tests.
3. Run `scripts/quality-gate.sh` before opening a pull request.
4. Never include credentials, private wheels, raw child output, or proprietary fixtures.

Bug reports should include the tool version, platform, Python version, sanitized module name, exit code, and whether the wheel is self-built. Do not attach a private wheel.
