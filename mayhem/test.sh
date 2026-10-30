#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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

# RUN the CppUTest binary build.sh produced (builddir/tests/unit/tests), the way upstream's ctest does.
# The UI must be headless-capable and the en_US.UTF-8 locale installed (see Dockerfile).
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
B="$SRC/builddir"
[ -x "$B/tests/unit/tests" ] || { echo "missing $B/tests/unit/tests: mayhem/build.sh did not build it" >&2; exit 1; }

cd "$B/tests/unit"
# Scripts.API checks connect-to-localhost over IPv4; with no non-loopback IPv4 address (docker
# --network none) getaddrinfo(AI_ADDRCONFIG) returns nothing for it, so skip just that group there.
excl=()
getent ahostsv4 localhost >/dev/null 2>&1 || excl=(-xsg Scripts)
out=$(WEECHAT_TESTS_ARGS="-p" \
      WEECHAT_EXTRA_LIBDIR="$B/src" \
      WEECHAT_TESTS_SCRIPTS_DIR="$SRC/tests/unit/scripts/python" \
      WEECHAT_TESTS_PLUGINS_LIB="$B/tests/unit/libweechat_unit_tests_plugins.so" \
      timeout 1200 ./tests -v "${excl[@]}" 2>&1 | tr -d '\000' | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g')
echo "$out" | tail -n 25

# CppUTest summary: "OK (N tests, ...)" or "Errors (F failures, N tests, ...)". Counts come from it,
# never from the exit status, so a neutered binary that prints nothing is reported as a failure.
if summary=$(echo "$out" | grep -E '^(OK \(|Errors \()' | tail -n 1) && [ -n "$summary" ]; then
  total=$(echo "$summary" | sed -n 's/.*[( ]\([0-9]\+\) tests,.*/\1/p')
  fails=$(echo "$summary" | sed -n 's/^Errors (\([0-9]\+\) failures.*/\1/p')
  ign=$(echo "$summary" | sed -n 's/.* \([0-9]\+\) ignored.*/\1/p')
  filt=$(echo "$summary" | sed -n 's/.* \([0-9]\+\) filtered out.*/\1/p')
  fails=${fails:-0}; ign=${ign:-0}; filt=${filt:-0}; total=${total:-0}
  passed=$(( total - fails - ign - filt ))
  if [ "$total" -gt 0 ]; then
    emit_ctrf "cpputest" "$passed" "$fails" "$(( ign + filt ))"
    exit $?
  fi
fi
echo "no CppUTest summary line found" >&2
emit_ctrf "cpputest" 0 1 0
