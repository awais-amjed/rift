#!/usr/bin/env bash
# Builds rift_ffenc.dll into OUT_DIR (build.sh) and runs its D3D11 input test
# (test_d3d11.c) on each encoder that opens on this computer, then decodes what
# it wrote (check_d3d11.py). Windows, in MSYS2's UCRT64 shell, with FFmpeg's
# command-line ffmpeg and Python on the path.
#
#   native/ffenc/test_windows.sh OUT_DIR
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=$(mkdir -p "${1:?usage: native/ffenc/test_windows.sh OUT_DIR}" && cd "$1" && pwd)
python=$(command -v python3 || command -v python) || {
  echo "test_windows.sh: needs Python on the path" >&2
  exit 1
}
command -v ffmpeg >/dev/null || {
  echo "test_windows.sh: needs ffmpeg on the path, to decode" >&2
  exit 1
}

"$here/build.sh" "$out"
"${CC:-gcc}" -O1 -g -Wall -I"$here" "$here/test_d3d11.c" -o "$out/test_d3d11.exe" \
  -L"$out" -lrift_ffenc -ld3d11 -ldxgi -ldxguid
export PATH="$out:$PATH"

for encoder in h264_nvenc h264_qsv h264_amf; do
  result=0
  "$out/test_d3d11.exe" "$out" "$encoder" || result=$?
  if [[ $result == 2 ]]; then
    echo "$encoder: skipped, it does not open here" >&2
    continue
  elif [[ $result != 0 ]]; then
    exit "$result"
  fi
  "$python" "$here/check_d3d11.py" "$out" "$encoder"
  # Returning from main with an encoder open must still end the process.
  timeout 10 "$out/test_d3d11.exe" "$out" "$encoder" --exit-open
done
