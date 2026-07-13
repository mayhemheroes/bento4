#!/usr/bin/env bash
#
# mayhem/test.sh — RUN Bento4's upstream pytest suite (Test/Pytest: mp4dash + aes known-answer
# tests). The suite drives the Release-built Bento4 tools that mayhem/build.sh staged in
# Source/Python/utils/bin (mp4dash's default --exec-dir) and asserts on their outputs.
# (Test/Python/runtests.py is legacy-broken upstream — it imports a `bento4` Python module and a
# Test/Data/test-001.mp4 fixture that no longer ship in the repo — so it is not runnable.)
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# The tools must already exist — build.sh stages them; do NOT compile here.
if [ ! -x "$SRC/Source/Python/utils/bin/mp4fragment" ]; then
  echo "FATAL: Source/Python/utils/bin/mp4fragment missing — mayhem/build.sh did not stage the test tools" >&2
  emit_ctrf pytest 0 1 0
  exit 1
fi

# The suite mkdir()s its per-test output dirs non-recursively — the parent must exist.
mkdir -p "$SRC/Test/Output/mp4dash"

out="$(BENTO4_HOME="$SRC" PYTHONPATH="$SRC/Source/Python/utils" python3 -m pytest Test/Pytest -q 2>&1)"
rc=$?
echo "$out"

passed=$(echo "$out" | grep -oE '[0-9]+ passed'  | tail -1 | grep -oE '[0-9]+' || echo 0)
failed=$(echo "$out" | grep -oE '[0-9]+ failed'  | tail -1 | grep -oE '[0-9]+' || echo 0)
skipped=$(echo "$out" | grep -oE '[0-9]+ skipped' | tail -1 | grep -oE '[0-9]+' || echo 0)
errors=$(echo "$out" | grep -oE '[0-9]+ error(s)?' | tail -1 | grep -oE '[0-9]+' || echo 0)
: "${passed:=0}" ; : "${failed:=0}" ; : "${skipped:=0}" ; : "${errors:=0}"

# Collection errors / a crashed pytest count as failures.
if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ] && [ "$errors" -eq 0 ]; then errors=1; fi
failed=$(( failed + errors ))

emit_ctrf pytest "$passed" "$failed" "$skipped"
