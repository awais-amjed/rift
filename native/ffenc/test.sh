#!/usr/bin/env bash
# Builds librift_ffenc.so into OUT_DIR (build.sh) and runs its tests against
# it on this computer's GPU. Linux only; needs a VAAPI encoder.
#
#   native/ffenc/test.sh OUT_DIR
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=$(mkdir -p "${1:?usage: native/ffenc/test.sh OUT_DIR}" && cd "$1" && pwd)

"$here/build.sh" "$out"
cc=${CC:-cc}
"$cc" -O1 -g -Wall -I"$here" -I/usr/include/libdrm "$here/test_dmabuf.c" \
  -o "$out/test_dmabuf" -L"$out" -lrift_ffenc -lva -lva-drm \
  -Wl,-rpath,"$out"
"$out/test_dmabuf"
