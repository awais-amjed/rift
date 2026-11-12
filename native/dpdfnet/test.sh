#!/usr/bin/env bash
# Builds the library into OUT_DIR (build.sh) and checks it: Ceva's own
# contract tests on the very objects it was linked from, then the library as
# the Rust crate uses it (test_model.c). Linux, or Windows in MSYS2's UCRT64
# shell. A test that needs a CPU feature this computer lacks is skipped, and
# said so.
#
#   native/dpdfnet/test.sh OUT_DIR
#
# Ceva's tests cover the public functions, each kernel against a plain C
# version of itself (in every rounding mode, between pages nothing may touch)
# and both AVX2 and AVX-VNNI kernels where the CPU has them. They are
# written for Linux. On Windows, where Ceva does not build, they run with
# three allowances, none of them in the code under test: the kernels'
# prototypes say System V (third_party/dpdfnet/sysv-kernels.patch), the guard
# pages come from test_windows/sys/mman.h, and __linux__ is defined to get
# past their own "Linux only" lines. Left out: the two that compare a stream
# through dlopen and Python, and the benchmark's statistics.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=$(mkdir -p "${1:?usage: native/dpdfnet/test.sh OUT_DIR}" && cd "$1" && pwd)
cc=${RIFT_DPDFNET_CC:-gcc}
"$here/build.sh" "$out"

src=$out/source
tests=$out/tests
rm -rf "$tests"
mkdir -p "$tests"
weights2=$src/models/dpdfnet2_48khz_hr/weights.f32
weights8=$src/models/dpdfnet8_48khz_hr/weights.f32
flags=(-O3 -DNDEBUG -std=gnu11 -Wall -Wextra -ffp-contract=off
  -I"$src/include" -I"$src/src" -I"$src/src/private")
exe=
if [[ $(uname -s) != Linux ]]; then
  flags+=(-D__linux__ -I"$here/test_windows")
  exe=.exe
fi

ran=0
skipped=0
# run <name> <args>: a test that returns 77 was skipped.
run() {
  local name=$1 result=0
  shift
  "$tests/$name$exe" "$@" >"$tests/$name.log" 2>&1 || result=$?
  if [[ $result == 77 ]]; then
    echo "skipped: $name ($(tail -n 1 "$tests/$name.log"))" >&2
    skipped=$((skipped + 1))
  elif [[ $result != 0 ]]; then
    echo "FAILED ($result): $name" >&2
    tail -n 20 "$tests/$name.log" >&2
    exit 1
  else
    ran=$((ran + 1))
  fi
}

# The public functions, on both models' objects and Ceva's runtime.c.
ceva=("$out"/obj/model*.o "$out/obj/runtime.o")
"$cc" "${flags[@]}" "$src/tests/public_contract.c" "${ceva[@]}" -o "$tests/public_contract$exe" -lm
run public_contract "$weights2" "$weights8"
"$cc" "${flags[@]}" "$src/tests/cpu_contract.c" "${ceva[@]}" -o "$tests/cpu_contract$exe" -lm
if grep -q -w avx2 /proc/cpuinfo && grep -q -w fma /proc/cpuinfo; then
  run cpu_contract 1
else
  run cpu_contract 0
fi
"$cc" "${flags[@]}" "$src/tests/concurrency_contract.c" "${ceva[@]}" \
  -o "$tests/concurrency_contract$exe" -lm -pthread
run concurrency_contract "$weights2" "$weights8"

# One model's graph and kernels, from inside: each test is linked to that
# model's objects alone and sees its private names. Flags as Ceva's
# CMakeLists.txt gives each.
# contract <size> <test> <name> [flags]
contract() {
  local size=$1 test=$2 name=$3
  shift 3
  "$cc" "${flags[@]}" -include "$src/src/private/namespace$size.h" -frounding-math "$@"     "$src/tests/$test.c" "$out"/obj/model"$size"_*.o -o "$tests/$name$exe" -lm
}
graph=(-DDPDF_X86_DISPATCH -DDPDF_CONV_PAIR -DDPDF_HAS_AVX_VNNI)
for size in 2 8; do
  weights=$src/models/dpdfnet${size}_48khz_hr/weights.f32
  for test in full_contract extended_contract layout_contract generated_gru_contract     conv_helpers_contract int8_contract int8_dispatch_contract fused_contract pair_contract; do
    contract $size $test model${size}_$test "${graph[@]}"
    run model${size}_$test "$weights"
  done
  # Its plain C version must keep its multiplies and adds in order.
  contract $size depthwise_contract model${size}_depthwise_contract "${graph[@]}"     -fno-tree-vectorize
  run model${size}_depthwise_contract "$weights"
  kernels=(pair_fused_contract)
  vnni=(fused_contract pair_contract)
  if [[ $size == 2 ]]; then
    kernels+=(wide_contract)
    vnni+=(wide_contract pair_fused_contract)
  fi
  for test in "${kernels[@]}"; do
    contract $size $test model${size}_$test -fno-tree-vectorize
    run model${size}_$test
  done
  # The same tests on the AVX-VNNI kernels, under the AVX2 ones' names.
  for test in "${vnni[@]}"; do
    contract $size $test model${size}_${test}_vnni -fno-tree-vectorize       -include "$src/src/private/int8_vnni_aliases.h" -DDPDF_TEST_AVX_VNNI
    run model${size}_${test}_vnni
  done
done

# The library itself.
if [[ $(uname -s) == Linux ]]; then
  "$cc" -O1 -g -Wall -I"$here" "$here/test_model.c" -o "$tests/test_model" \
    -L"$out" -lrift_dpdfnet -lm
  export LD_LIBRARY_PATH=$out${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
else
  "$cc" -O1 -g -Wall -I"$here" "$here/test_model.c" "$here/test_registers.S" \
    -o "$tests/test_model.exe" -L"$out" -lrift_dpdfnet
  export PATH="$out:$PATH"
fi
run test_model

echo "native/dpdfnet: $ran tests passed, $skipped skipped"
