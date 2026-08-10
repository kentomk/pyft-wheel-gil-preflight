#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$project_root"
expected_commit_message=$(git log -1 --format=%s)

jq -e --arg expected_commit_message "$expected_commit_message" '
  .schemaVersion == 2 and .action == "update" and .owner == "kentomk" and
  .name == "pyft-wheel-gil-preflight" and
  (.description | type == "string" and length >= 20 and length <= 160) and
  (.topics | type == "array" and length >= 1 and length <= 10 and index("kento-oss") != null and all(type == "string")) and
  .candidateId == "20260720T012824Z-0915" and
  (.targetUsers | type == "string" and length >= 10 and length <= 500) and
  (.jobToBeDone | type == "string" and length >= 10 and length <= 1000) and
  (.distributionPath | type == "string" and length >= 10 and length <= 500) and
  (.successMetric | type == "string" and length >= 10 and length <= 500) and
  .reviewAfterDays == 1 and .opportunityScore == 79 and
  (.demandEvidence | type == "array" and length >= 3 and all(type == "object" and
    (.url | startswith("https://")) and (.kind | test("^[a-z][a-z0-9-]{2,49}$")) and
    (.independenceKey | length >= 3 and length <= 200))) and
  ((.demandEvidence | map(.independenceKey | ascii_downcase) | unique | length) >= 3) and
  ((.demandEvidence | map(.kind) | unique | length) >= 2) and
  (.alternatives | type == "array" and length >= 3 and all(type == "object" and
    (.name | length >= 2 and length <= 200) and (.url | startswith("https://")) and
    .tested == true and (.gap | length >= 10 and length <= 1000))) and
  .duplicateSearch.completed == true and (.duplicateSearch.summary | length >= 20) and
  (.differentiation | length >= 20) and .testCommand == "scripts/publisher-gate.sh" and
  .license == "MIT" and .commitMessage == $expected_commit_message
' publish-request.json >/dev/null

jq -e --slurpfile request publish-request.json '
  .schemaVersion == 1 and .candidateId == $request[0].candidateId and
  .owner == $request[0].owner and .author == "@kentomk" and
  .automatedAgent == true and
  (.createdBy | test("Matsuki Kento") and test("@kentomk") and test("AI|automated"; "i"))
' .kento-oss.json >/dev/null

grep -Eq '^## Installation\b' README.md
grep -Eq '^## Quick start\b' README.md
grep -Fq 'pyft-wheel-gil-preflight --help' README.md
grep -Fq 'check --help' README.md
grep -Eq '^## Runtime prerequisite\b' README.md
grep -Fq 'Py_GIL_DISABLED=1' README.md
grep -Fq 'returns exit ' README.md
grep -Fq 'with one actionable message' README.md
grep -Fq 'No wheel or' README.md
grep -Fq 'network access is needed for this prerequisite check' README.md
grep -q '60-second quick start' README.md
grep -q 'Matsuki Kento' README.md
grep -q '@kentomk' README.md
grep -Eiq 'AI|automated' README.md
grep -q 'github.com/kentomk/pyft-wheel-gil-preflight/releases/tag/v0.1.2' README.md
grep -Fq "checksum_matches=\$(grep -Ec" README.md
grep -Fq "test \"\$checksum_matches\" -eq 1" README.md
# shellcheck disable=SC2016
checksum_pattern='grep -E "^[0-9a-fA-F]{64}  ${archive}$" SHA256SUMS'
grep -Fq "$checksum_pattern" README.md
grep -Fq "extract_dir=\$(mktemp -d)" README.md
grep -Fq "tar -xzf \"\$archive\" -C \"\$extract_dir\"" README.md
grep -Fq 'expected_binary="$extract_dir/${archive%.tar.gz}/pyft-wheel-gil-preflight"' README.md
grep -Fq 'test -f "$expected_binary" && test ! -L "$expected_binary"' README.md
grep -Fq "trap 'rm -rf \"\$extract_dir\"' EXIT HUP INT TERM" README.md
grep -Fq "unsafe_member=\$(tar -tzf \"\$archive\" | grep -E '(^/|(^|/)\\.\\.(\\/|$))' || true)" README.md
grep -Fq "test -z \"\$unsafe_member\" || { echo 'archive contains an unsafe member path' >&2; exit 2; }" README.md
grep -Fq 'uses: kentomk/pyft-wheel-gil-preflight@aa3c88484d9642f4ed8d3a38a5a1aa5d497fa458 # v0.1.2 release revision' README.md
if grep -Eq 'pyft-wheel-gil-preflight(@|_v|/releases/tag/)v0\.1\.[01]' README.md; then
  printf '%s\n' 'README contains a stale release reference' >&2
  exit 1
fi
if grep -q 'FULL_COMMIT_SHA' README.md; then
  printf '%s\n' 'README still contains the Action SHA placeholder' >&2
  exit 1
fi
if grep -q 'After the first release' README.md; then
  printf '%s\n' 'README still describes the published project as unreleased' >&2
  exit 1
fi

if grep -q 'No released version exists yet' SECURITY.md; then
  printf '%s\n' 'SECURITY.md still describes the published project as unreleased' >&2
  exit 1
fi
grep -Eq 'uses: actions/checkout@[0-9a-f]{40}([[:space:]]|$)' .github/workflows/ci.yml
grep -Eq 'uses: actions/setup-go@[0-9a-f]{40}([[:space:]]|$)' .github/workflows/ci.yml
if grep -Eq 'uses: actions/(checkout|setup-go)@v[0-9]' .github/workflows/*.yml action.yml; then
  printf '%s\n' 'mutable GitHub Action reference found' >&2
  exit 1
fi
