#!/usr/bin/env bash
#
# mayhem/test.sh — RUNS dunst's own greatest suite (test/test, built by mayhem/build.sh with the
# project's normal flags) and maps its summary line to CTRF. Fails if the summary is absent, so a
# patch that makes the runner exit early cannot pass.
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

[ -x test/test ] || { echo "test/test missing — mayhem/build.sh should have built it" >&2; exit 1; }

# the dbus suite needs a session bus; fall back to a private one when none is running
RUNNER=(./test/test -v)
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null; then
  RUNNER=(dbus-run-session -- ./test/test -v)
fi

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
TESTDIR=./test timeout 600 "${RUNNER[@]}" >"$out" 2>&1
rc=$?
cat "$out"

total="$(sed -n 's/^Total: \([0-9]\+\) tests.*/\1/p' "$out" | tail -1)"
counts="$(sed -n 's/^Pass: \([0-9]\+\), fail: \([0-9]\+\), skip: \([0-9]\+\)\./\1 \2 \3/p' "$out" | tail -1)"
if [ -z "$total" ] || [ -z "$counts" ]; then
  echo "greatest summary line not found — suite did not run to completion (rc=$rc)" >&2
  emit_ctrf "greatest" 0 1 0
  exit 1
fi
read -r passed failed skipped <<<"$counts"
[ "$rc" -eq 0 ] || failed=$(( failed > 0 ? failed : 1 ))
[ "$passed" -ge 1 ] || failed=$(( failed + 1 ))
emit_ctrf "greatest" "$passed" "$failed" "$skipped"
