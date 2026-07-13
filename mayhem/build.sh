#!/usr/bin/env bash
#
# mayhem/build.sh — build Bento4's fuzz harnesses, sanitized CLI targets, and its test suite.
#
# Produces:
#   /mayhem/fuzz_Find                libFuzzer harness over AP4_String::Find (ASan+UBSan)
#   /mayhem/fuzz_Find-standalone     run-once reproducer for the same harness
#   /mayhem/mp4dump                  libFuzzer harness over the mp4dump atom-parse path
#   /mayhem/mp4dump-standalone       run-once reproducer for the same harness
#   Source/Python/utils/bin/         Release-built Bento4 tools for the upstream pytest suite
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# ASan + UBSan, halting (default here; the base image also exports this same value as ENV).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DISABLE the benign `nonnull-attribute`/`returns-nonnull-attribute` UBSan checks — appended
# UNCONDITIONALLY (last wins) so it applies whether SANITIZER_FLAGS came from the base image ENV or
# the default above. Bento4's AP4_DataBuffer copy path calls AP4_CopyMemory(dst, NULL, 0) on
# zero-length buffers — a harmless memcpy(_, NULL, 0) that trips this check on essentially EVERY
# valid MP4 input, making the tool exit nonzero/abort on all seeds and emptying Mayhem's optimized
# corpus (edges_covered=0). ASan still catches any real NULL dereference; the rest of UBSan stays
# halting so genuine UB is still caught.
SANITIZER_FLAGS="$SANITIZER_FLAGS -fno-sanitize=nonnull-attribute,returns-nonnull-attribute"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 1) Sanitized build of libap4 (the fuzzed AP4 parsing code is instrumented).
rm -rf "$SRC/cmakebuild-mayhem"
cmake -B "$SRC/cmakebuild-mayhem" \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
      -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
      -DBUILD_APPS=ON
cmake --build "$SRC/cmakebuild-mayhem" -j"$MAYHEM_JOBS" --target ap4

# Include dirs: Ap4.h pulls headers from every Source/C++ subdir — pass them all.
AP4_INCLUDES=()
for d in "$SRC"/Source/C++/*/; do AP4_INCLUDES+=(-I"$d"); done

$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o

# 2) fuzz_Find harness: libFuzzer binary + standalone run-once reproducer.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    "$SRC/mayhem/fuzz_Find.cpp" -I"$SRC/Source/C++/Core" \
    "$SRC/cmakebuild-mayhem/libap4.a" -o /mayhem/fuzz_Find
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS \
    "$SRC/mayhem/fuzz_Find.cpp" -I"$SRC/Source/C++/Core" /tmp/standalone_main.o \
    "$SRC/cmakebuild-mayhem/libap4.a" -o /mayhem/fuzz_Find-standalone

# 3) mp4dump harness: in-process libFuzzer over the mp4dump atom-parse loop (target 'mp4dump').
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    "$SRC/mayhem/fuzz_mp4dump.cpp" "${AP4_INCLUDES[@]}" \
    "$SRC/cmakebuild-mayhem/libap4.a" -o /mayhem/mp4dump
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS \
    "$SRC/mayhem/fuzz_mp4dump.cpp" "${AP4_INCLUDES[@]}" /tmp/standalone_main.o \
    "$SRC/cmakebuild-mayhem/libap4.a" -o /mayhem/mp4dump-standalone

# 5) Test-suite build with NORMAL flags: Release tools for Test/Pytest (mp4dash drives
#    mp4fragment/mp4info/... via Source/Python/utils/bin — its default --exec-dir).
rm -rf "$SRC/cmakebuild-test"
cmake -B "$SRC/cmakebuild-test" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
      -DBUILD_APPS=ON
cmake --build "$SRC/cmakebuild-test" -j"$MAYHEM_JOBS"
rm -rf "$SRC/Source/Python/utils/bin"
mkdir -p "$SRC/Source/Python/utils/bin"
for app in "$SRC"/Source/C++/Apps/*/; do
  tool="$(basename "$app" | tr '[:upper:]' '[:lower:]')"
  if [ -f "$SRC/cmakebuild-test/$tool" ]; then
    cp "$SRC/cmakebuild-test/$tool" "$SRC/Source/Python/utils/bin/"
  fi
done
