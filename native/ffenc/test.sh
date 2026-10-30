#!/usr/bin/env bash
# Builds librift_ffenc.so into OUT_DIR (build.sh) and runs its tests against
# it on this computer's GPU, each test only where its encoder opens. Linux only.
#
#   native/ffenc/test.sh OUT_DIR
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=$(mkdir -p "${1:?usage: native/ffenc/test.sh OUT_DIR}" && cd "$1" && pwd)

"$here/build.sh" "$out"
cc=${CC:-cc}
"$cc" -O1 -g -Wall -I"$here" "$here/test_nvenc_geometry.c" \
  "$here/nvenc_gl_geometry.c" -o "$out/test_nvenc_geometry" -lm
"$out/test_nvenc_geometry"

# A test that exits 2 had no encoder to test on.
run_on_gpu() {
  local result=0
  "$@" || result=$?
  if [[ $result == 2 ]]; then
    echo "$1: skipped, its encoder does not open here" >&2
  elif [[ $result != 0 ]]; then
    exit "$result"
  fi
}
"$cc" -O1 -g -Wall -I"$here" -I/usr/include/libdrm "$here/test_dmabuf.c" \
  -o "$out/test_dmabuf" -L"$out" -lrift_ffenc -lva -lva-drm \
  -Wl,-rpath,"$out"
run_on_gpu "$out/test_dmabuf"
