#!/usr/bin/env bash
#
# mayhem/build.sh — builds dunst three ways, all offline:
#   1. the project objects, sanitized + DWARF 3 + SanCov, out of tree in mayhem/build/obj
#   2. one libFuzzer binary and one -standalone reproducer per harness in mayhem/harnesses
#   3. upstream's own test suite (test/test) with the project's NORMAL flags, for mayhem/test.sh
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs come from the ENVIRONMENT (overridable), with sane defaults — no if-statements,
# just parameter-expansion fallbacks. Default sanitizers are the base's ASan+UBSan (halting); override
# per build via the Dockerfile's `--build-arg SANITIZER_FLAGS="..."`.
# NB: SANITIZER_FLAGS uses `=` (no colon) on purpose — `=` only fills when the var is UNSET, so an
# explicit EMPTY value (`--build-arg SANITIZER_FLAGS=`) is honored and builds with NO sanitizers
# (useful when you want the program's natural crash / full backtrace, not an ASan report). The other
# knobs use `:=` (default on empty too). MAYHEM_JOBS sets build parallelism (falls back to nproc).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries DWARF debug info INDEPENDENTLY of the sanitizer off-switch (so an empty
# SANITIZER_FLAGS still yields DWARF symbols). DWARF MUST be < 4 (Mayhem triage can't read >=4); clang-19's
# plain `-g` emits DWARF-5, so `-gdwarf-3` is explicit. Apply $DEBUG_FLAGS to the fuzz/harness/standalone
# builds (NOT the test/oracle build). Rust/Go carry the same intent via their language flags below.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3}"
: "${GO_DEBUG_FLAGS:=-gcflags=all=-N -l}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
# COVERAGE_FLAGS: empty by default → no effect on the normal oracle build. Set it via the Dockerfile's
# `--build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping"` to instrument the TEST
# build for source-coverage measurement (how much of the project the test suite actually exercises —
# a quality signal for the oracle; complements the anti-reward-hack sabotage check). APPEND it to the
# test build's compile+link flags in step 3 (NOT the fuzz build); after `test.sh` runs, merge with
# `llvm-profdata` and report with `llvm-cov`. Empty value is honored (`=`, not `:=`).
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS RUST_DEBUG_FLAGS GO_DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

OBJ="$SRC/mayhem/build/obj"
rm -rf "$SRC/mayhem/build"
mkdir -p "$OBJ"

# 1) sanitized project objects (everything but main.c and the wayland backend)
PKGS=(gio-2.0 gdk-pixbuf-2.0 glib-2.0 pangocairo x11 xinerama xext xrandr xscrnsaver)
PKG_CFLAGS="$(pkg-config --cflags "${PKGS[@]}")"
PKG_LIBS="$(pkg-config --libs "${PKGS[@]}")"
CPPDEFS=(-D_DEFAULT_SOURCE '-DVERSION="fuzz"' '-DSYSCONFDIR="/etc/xdg"' -DENABLE_X11)
PROJ_FLAGS=(-std=gnu11 -O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link
            "${CPPDEFS[@]}" $PKG_CFLAGS -Wno-unknown-warning-option -Wno-c2y-extensions)

SRCS=()
for f in src/*.c src/x11/*.c; do
  [ "$f" = src/main.c ] || SRCS+=("$f")
done
OBJS=()
for f in "${SRCS[@]}"; do OBJS+=("$OBJ/$(echo "${f%.c}" | tr / _).o"); done

printf '%s\n' "${SRCS[@]}" | xargs -P "$MAYHEM_JOBS" -I{} bash -c \
  'f="$1"; exec '"$CC"' "${@:2}" -c "$f" -o "'"$OBJ"'/$(echo "${f%.c}" | tr / _).o"' _ {} "${PROJ_FLAGS[@]}"

$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OBJ/lsan_off.o"

# 2) harnesses: fuzzer + standalone reproducer
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"
for h in mayhem/harnesses/fuzz_*.c; do
  n="$(basename "${h%.c}")"
  $CC "${PROJ_FLAGS[@]}" -Isrc -c "$h" -o "$OBJ/$n.o"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OBJ/$n.o" "${OBJS[@]}" "$OBJ/lsan_off.o" \
      $PKG_LIBS -lm -lrt -o "/mayhem/$n"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$OBJ/standalone_main.o" "$OBJ/$n.o" "${OBJS[@]}" "$OBJ/lsan_off.o" \
      $PKG_LIBS -lm -lrt -o "/mayhem/$n-standalone"
done

# 3) upstream's test suite, normal flags (in-tree objects are gitignored)
# (LDFLAGS goes through the environment: on make's command line it would replace the pkg-config libs)
env -u CFLAGS -u CPPFLAGS CFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" \
    make -j"$MAYHEM_JOBS" WAYLAND=0 DUNSTIFY=0 test/test
