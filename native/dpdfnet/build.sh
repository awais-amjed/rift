#!/usr/bin/env bash
# Builds Ceva's own runtime for DPDFNet into OUT_DIR, with the two models'
# weights inside it (rift_dpdfnet.h says why it is a library of its own). The
# Linux and Windows runners' CMake run it; it can also run by hand.
#
#   native/dpdfnet/build.sh OUT_DIR
#
# On Windows it makes rift_dpdfnet.dll, in MSYS2's UCRT64 shell with MinGW's
# gcc and patch, as native/ffenc/build.sh does. On Linux it makes
# librift_dpdfnet.so and needs gcc, which is what Ceva builds with: their
# build refuses any other compiler. The source and the weights come in one
# download, taken once into OUT_DIR, or from RIFT_DPDFNET_TARBALL, and its
# sha256 checked either way. Nothing is rebuilt while the inputs are the same.
# The source and the objects stay in OUT_DIR, for test.sh.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
patches=$here/../../third_party/dpdfnet
out=$(mkdir -p "${1:?usage: native/dpdfnet/build.sh OUT_DIR}" && cd "$1" && pwd)

# github.com/ceva-ip/DPDFNet, branch optimized-inference, folder
# optimized_inference (third_party/dpdfnet/RIFT_PATCHES.md).
commit=98df76589cdf7787553b9e05a112d5820e6c8db6
sha256=3ab42d6a552102361d9d3f02f59ce74bbaa8738c64e3fd8dba229b2697d22387
case "$(uname -s)" in
  Linux) os=linux library=$out/librift_dpdfnet.so ;;
  MINGW* | MSYS*) os=windows library=$out/rift_dpdfnet.dll ;;
  *)
    echo "native/dpdfnet/build.sh: nothing to build on $(uname -s)" >&2
    exit 1
    ;;
esac
# Not CC: the Linux release sets that to the clang libwebrtc needs.
cc=${RIFT_DPDFNET_CC:-gcc}

stamp=$(
  {
    echo "$commit $sha256 $("$cc" -dumpfullversion -dumpmachine | tr '\n' ' ')"
    cat "$patches"/*.patch "$here"/*.c "$here"/*.h "$here"/*.S "$here"/exports.map "$0"
  } | sha256sum | cut -d' ' -f1
)
if [[ -f $library && -f $out/.stamp && $(<"$out/.stamp") == "$stamp" ]]; then
  exit 0
fi
rm -f "$out/.stamp" "$out/build.log"

# The compiler's output, warnings included, goes to a log that is shown only
# if a step fails.
quietly() {
  if ! "$@" >>"$out/build.log" 2>&1; then
    tail -n 40 "$out/build.log" >&2
    exit 1
  fi
}

tarball=${RIFT_DPDFNET_TARBALL:-$out/dpdfnet-$commit.tar.gz}
# tar takes the C: of a Windows path for a host to fetch it from.
if [[ $os == windows ]]; then tarball=$(cygpath -u "$tarball"); fi
if [[ ! -f $tarball ]]; then
  curl -fsSL "https://github.com/ceva-ip/DPDFNet/archive/$commit.tar.gz" -o "$tarball.part"
  mv "$tarball.part" "$tarball"
fi
echo "$sha256  $tarball" | sha256sum -c --quiet
src=$out/source
rm -rf "$src" "$out/obj"
mkdir -p "$src" "$out/obj"
tar -C "$src" --strip-components=2 -xzf "$tarball" "DPDFNet-$commit/optimized_inference"
(cd "$src" && sha256sum -c --quiet models/SHA256SUMS)
for patch in "$patches"/*.patch; do
  patch -d "$src" -p1 --quiet <"$patch"
done
if [[ $os == windows ]]; then
  # What only an ELF object can carry. The kernels are leaf functions that
  # never move the stack pointer, so Windows needs no unwind data in their
  # place.
  find "$src/src" -name '*.S' -exec sed -i -E \
    -e '/^[[:space:]]*\.(hidden|type|size)[[:space:]]/d' \
    -e '/^[[:space:]]*\.cfi_(start|end)proc/d' \
    -e '/^\.section \.note\.GNU-stack/d' {} +
fi

# As Ceva's CMakeLists.txt builds it, flag for flag, less the compiler profile
# its release build trains for DPDFNet-8: each model's graph and the kernels
# under it compiled once per model, with the model's own names
# (namespaceN.h), AVX2 and AVX-VNNI switched on only in the files that are
# reached after the CPU was asked.
flags=(-O3 -DNDEBUG -std=gnu11 -Wall -Wextra -ffp-contract=off -fno-math-errno
  -fvisibility=hidden -I"$src/include" -I"$src/src" -I"$src/src/private"
  -DDPDF_X86_DISPATCH -DDPDF_QASM64 -DDPDF_QFUSED64 -DDPDF_QPAIR_FIXED
  -DDPDF_HAS_AVX_VNNI)
if [[ $os == linux ]]; then flags+=(-fPIC); fi
# The assembler leaves the AVX-VNNI kernels' layout as Ceva measured it.
vnni=(-Wa,-malign-branch-boundary=0)

# compile <model> <source> [flags]: into obj/, named after the model.
compile() {
  local size=$1 source=$2 name
  shift 2
  name=$(basename "$(dirname "$source")")_$(basename "${source%.*}")
  quietly "$cc" "${flags[@]}" "${model_flags[@]}" "$@" -c "$source" \
    -o "$out/obj/model${size}_$name.o"
}
for size in 2 8; do
  model=$src/src/models/dpdfnet${size}_48khz_hr
  model_flags=(-DDPDF_MODEL_SIZE=$size -include "$src/src/private/namespace$size.h")
  if [[ $size == 2 ]]; then
    model_flags+=(-DDPDF_QFUSED256 -DDPDF_QPAIR_FUSED64)
  else
    model_flags+=(-DDPDF_QBATCH_FUSED64_AVX2 -Wa,-mbranches-within-32B-boundaries)
  fi
  for source in "$src/src/model_backend.c" "$model/generated_model.c" \
    "$src/src/common/full_ops.c" "$src/src/common/dpdf_dprnn.c" \
    "$src/src/common/extended_ops.c" "$src/src/common/qdot64_fixed_avx2.S" \
    "$src/src/common/qdot4pair_fixed_avx2.S" "$model/qaffine64_fused_avx2.S"; do
    compile $size "$source"
  done
  compile $size "$src/src/common/avx2.c" -mavx2 -mfma
  compile $size "$src/src/common/int8.c" -mavx2 -mfma
  compile $size "$src/src/common/fp16.c" -mavx2 -mfma -mf16c
  compile $size "$src/src/common/int8_vnni.c" -mavx2 -mfma -mavxvnni "${vnni[@]}"
  for source in "$src/src/common/qdot64_fixed_vnni.S" \
    "$src/src/common/qdot4pair_fixed_vnni.S" "$model/qaffine64_fused_vnni.S"; do
    compile $size "$source" "${vnni[@]}"
  done
  if [[ $size == 2 ]]; then
    compile 2 "$model/qaffine256_fused_avx2.S"
    compile 2 "$model/qaffine4pair64_fused_avx2.S"
    compile 2 "$model/qaffine256_fused_vnni.S" "${vnni[@]}"
    compile 2 "$model/qaffine4pair64_fused_vnni.S" "${vnni[@]}"
  else
    compile 8 "$src/src/models/dpdfnet2_48khz_hr/qaffine4pair64_fused_avx2.S"
  fi
done
quietly "$cc" "${flags[@]}" -c "$src/src/runtime.c" -o "$out/obj/runtime.o"
quietly "$cc" "${flags[@]}" -I"$here" -c "$here/rift_dpdfnet.c" -o "$out/obj/rift_dpdfnet.o"
# The weights: .incbin looks for them under -I.
quietly "$cc" -I"$src/models" -c "$here/weights.S" -o "$out/obj/weights.o"

# Only Rift's own functions leave the library (rift_dpdfnet.h). The linker's
# map, beside it, names the function at each offset, for a crash's log.
if [[ $os == linux ]]; then
  quietly "$cc" -shared "$out"/obj/*.o -o "$library.part" -lm \
    -Wl,--version-script="$here/exports.map" -Wl,-Bsymbolic -Wl,-z,defs \
    -Wl,-Map,"$out/librift_dpdfnet.map"
else
  # A DLL exports only what is marked to (RIFT_DPDFNET_EXPORT), and carries
  # MinGW's own runtime inside it, so it needs nothing the app does not ship.
  # Linked in a folder of its own under its real name, which a DLL keeps
  # inside it (test.sh links a program to it).
  mkdir -p "$out/part"
  quietly "$cc" -shared "$out"/obj/*.o -o "$out/part/rift_dpdfnet.dll" \
    -static-libgcc -Wl,--exclude-libs,ALL -Wl,-Map,"$out/rift_dpdfnet.map"
  mv "$out/part/rift_dpdfnet.dll" "$library.part"
  rmdir "$out/part"
fi
mv "$library.part" "$library"
echo "$stamp" >"$out/.stamp"
