#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$project_root"

jq -e '
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
  .license == "MIT" and .commitMessage == "Document verified public install paths"
' publish-request.json >/dev/null

jq -e --slurpfile request publish-request.json '
  .schemaVersion == 1 and .candidateId == $request[0].candidateId and
  .owner == $request[0].owner and .author == "@kentomk" and
  .automatedAgent == true and
  (.createdBy | test("Matsuki Kento") and test("@kentomk") and test("AI|automated"; "i"))
' .kento-oss.json >/dev/null

grep -Eq '^## Installation\b' README.md
grep -Eq '^## Quick start\b' README.md
grep -q '60-second quick start' README.md
grep -q 'Matsuki Kento' README.md
grep -q '@kentomk' README.md
grep -Eiq 'AI|automated' README.md
grep -q 'github.com/kentomk/pyft-wheel-gil-preflight/releases/tag/v0.1.0' README.md
grep -q 'kentomk/pyft-wheel-gil-preflight@98b6960783c9d0423a543c12de796275414b1e32' README.md
if grep -q 'FULL_COMMIT_SHA' README.md; then
  printf '%s\n' 'README still contains the Action SHA placeholder' >&2
  exit 1
fi
if grep -q 'After the first release' README.md; then
  printf '%s\n' 'README still describes the published project as unreleased' >&2
  exit 1
fi
grep -Eq 'uses: actions/checkout@[0-9a-f]{40}([[:space:]]|$)' .github/workflows/ci.yml
grep -Eq 'uses: actions/setup-go@[0-9a-f]{40}([[:space:]]|$)' .github/workflows/ci.yml
if grep -Eq 'uses: actions/(checkout|setup-go)@v[0-9]' .github/workflows/*.yml action.yml; then
  printf '%s\n' 'mutable GitHub Action reference found' >&2
  exit 1
fi
